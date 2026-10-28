# DeadPark: Matinha - how the game mechanics were built

A reusable reference for the systems in this game (Godot 4.7, GDScript, Jolt physics, ~19k lines). Written so each section can be lifted into another project: what the system does, the key scripts/nodes/signals, the pattern behind it, and the gotchas.

> Paths are relative to the game project (`scripts/...`). The game itself lives on the author's PC; this repo holds only the docs. Verified against the source in May-Oct 2026 state of the project (day 7+ content, Zone 2, haunted house).

## Contents
0. [Architecture patterns used everywhere](#0-architecture-patterns-used-everywhere)
1. [Player, inventory and hotbar](#1-player-inventory-and-hotbar)
2. [Interaction, HUD and dialogue](#2-interaction-hud-and-dialogue)
3. [Day/night loop and blood moon](#3-daynight-loop-and-blood-moon)
4. [Generators and power](#4-generators-and-power)
5. [Rides and the Ride Manager PC app](#5-rides-and-the-ride-manager-pc-app)
6. [Economy, reports and shop](#6-economy-reports-and-shop)
7. [Phone and its apps](#7-phone-and-its-apps)
8. [Pause, save and load](#8-pause-save-and-load)
9. [Visitors, trash and the janitor](#9-visitors-trash-and-the-janitor)
10. [Workers (janitor, technician)](#10-workers-janitor-technician)
11. [Intruders and killer AI](#11-intruders-and-killer-ai)
12. [Combat, weapons and blood FX](#12-combat-weapons-and-blood-fx)
13. [Cameras and investigation](#13-cameras-and-investigation)
14. [Cheats and debug map](#14-cheats-and-debug-map)
15. [Audio](#15-audio)
16. [Look: PSX shader, minimap, UI style](#16-look-psx-shader-minimap-ui-style)
17. [Asset import and bake tools](#17-asset-import-and-bake-tools)
18. [Reuse checklist for a new game](#18-reuse-checklist-for-a-new-game)

---

## 0. Architecture patterns used everywhere

**One autoload, many self-contained nodes.** `project.godot` has a single autoload: `Game` (`scripts/game.gd`). It holds everything that must survive scene changes (inventory, money, story flags, generator/ride flags, options) and exposes **signals** (`inventory_changed`, `equipped_changed(id)`, `money_changed(amount)`, `generator_changed`, `power_changed`, `ammo_changed`, `photos_changed`, `text_received(from, text)`, `unread_changed(count)`). Everything else listens; nothing polls `Game`.

**Tuning numbers in one file.** `scripts/economy.gd` (`extends RefCounted`, only `const`s) holds every price, time, count, range and spot. Other scripts `preload` it as `Economy`. Changing game balance never means hunting through scripts. Positions can be overridden by `Marker3D` nodes in the map (e.g. `Generator3Spot`, `DumpsterSpot`, `Cam_<id>`), with an `Economy` constant as fallback.

**Code-built UI and props.** Menus (`inventory.gd`, `shop.gd`, `phone.gd`, ...) are `CanvasLayer`/`Control` scripts that build their whole tree in `_build()`, so there are no `.tscn` files to keep in sync. Procedural rides use `rides/ride_kit.gd` (box/cylinder/ring/rod helpers). Trade-off: harder to edit visually, but trivially diffable and fast to generate.

**Duck-typed interaction.** The player's ray finds a node and walks up parents until `has_method("interact")`. Interactables implement `interact(player)`, optionally `prompt() -> String` (HUD text), `use_item(id) -> bool` (called by the inventory's Use command or when holding a tool). No base class or interface needed.

**Groups as service locator.** `get_first_node_in_group("player" | "day_night" | "killer" | "worker" | "ride" | "generator" | "intruders" | "visitor_manager" | "trash_manager" | "minimap" | "phone" | "dialogue")`. Used instead of hard node paths so scenes can be rearranged.

**Managers built by the clock.** `day_night.gd` creates the sub-managers (visitors, trash, cameras, reports, PSX look, park additions) at load. The main-menu background reuses the same park scene with those switched off (`day_night._ready` checks for the menu).

**Pause model.** Full-screen menus set `get_tree().paused = true` and use `process_mode = PROCESS_MODE_ALWAYS` on themselves (`inventory.gd`, `pause_menu.gd`). Gotcha: each menu must check `_can_open()` so Esc/I don't stack menus over a dialogue, the PC or the camera feed.

**Write for the user in comments.** Scripts open with a `##` doc comment saying what the node does, who makes it ("Made by park_additions.gd") and its keys. Keep this habit; it is what made 19k lines navigable.

**Gotcha - backup folders and `class_name`.** Backup copies of scripts inside the project with a `class_name` (e.g. `BloodFx`) hijack Godot's global class cache and cause parse errors. Keep backups in `scenes/backups/` with an empty `.gdignore` file in it.

---

## 1. Player, inventory and hotbar

**Files:** `scripts/player.gd` (`CharacterBody3D`, ~960 lines), `ui/inventory.gd`, `ui/hotbar.gd`, `finger_curl.gd`, `game.gd` (`ITEMS`).

**Player** (first person): WASD via `Input.is_physical_key_pressed(KEY_*)` (no InputMap needed; layout independent), Shift run, Space jump, mouse look with head pitch node, E use, F flashlight, R reload, I inventory, Esc pause, Up arrow phone. Signals: `health_changed(health, max)`, `arm_changed(attached, carried)`, `arm_lost`, `died`. `starts_armed` export lets the debug map spawn with a hammer while the real game starts empty-handed. A `can_move`-style flag lets menus freeze input.

**Hands/viewmodel:** first-person arms are a separate imported mesh under the camera. The imported right hand was broken, so `_build_right_fist()` mirrors the left arm. Held items are parented to the fist with per-item offsets (`hold` data in `Game.ITEMS`: a point on the head and one on the handle in the model's own space, so any model can be gripped). Hand bob/sway is `_move_arms`. `finger_curl.gd` curls finger bones around a handle.

**Footsteps by surface:** ray down; a node (or parent) with a `"surface"` meta wins, then a name table `SURFACE_BY_NODE`, else concrete.

**Motion blur:** a full-screen shader under the HUD, strength from camera angular speed (swings and flicks only, not normal looking).

**Inventory data model:** `Game.ITEMS` is a dictionary `id -> {name, read text, model, hold, use...}`; `Game.items: Array[String]`, `Game.equipped: String`. Add an item = add one dictionary entry + (optionally) a model. Starting loadout: `STARTING_ITEMS`; cabinet storage: `cabinet_items` (15 slots) with `storage_cabinet.gd`/`storage_menu.gd`.

**Inventory UI (`inventory.gd`):** a carousel of 3D models spinning in the middle (SubViewport), A/D to pick, W/S to pick a command (Use/Examine...), plus Photos/Map/Memo/Options tabs, and a live **ECG heartbeat** drawn from a polyline template (flat, P bump, QRS spike, T wave) whose speed/height depend on health band (Fine/Caution/Danger). Opening pauses the game and plays the title music.

**Hotbar (`hotbar.gd`):** one slot per carried item (notes/maps/phone excluded - those live in the menu or pocket), mouse wheel or 1-6 selects, writes `Game.equipped`, which fires `equipped_changed`. The player reacts to that signal to swap the held model. The phone slot shows an unread badge (`unread_changed`).

**Gotchas:** keep "held in hand" logic in the player and "what exists" in `Game`, so saves only need data. Items that shouldn't take a slot are marked in `ITEMS` (notes, maps, phone).

---

## 2. Interaction, HUD and dialogue

**HUD (`hud.gd`):** crosshair turns yellow over anything with `interact`, and shows `E <prompt>`; the prompt comes from `prompt()` or the node name humanized ("LightSwitch2" -> "Light Switch"). Also red hurt flash, arm status, and a pulsing "vision" overlay (blurred icon + church bell) when the arm comes off.

**Dialogue (`ui/dialogue_box.gd`):** `await dialogue.say(speaker, lines)`, `shout(speaker, text, seconds)` (auto-fading line), `await choose(speaker, options)` returns the picked index. Typewriter text, auto-growing box, cinematic black bars + camera zoom via `cinematic(true, player)`. Signals `finished`, `line_started(i)` (speaker can react per line), `chosen(i)`. Keys pressed in the first moment of a choice are ignored (they closed the previous line).

**Story cards (`story_card.gd`, `story_texts.gd`):** full-screen text cards between beats (night falls, training dusk). All story strings live in `story_texts.gd` keyed per character so workers' lore is data, not code.

---

## 3. Day/night loop and blood moon

**File:** `scripts/world/day_night.gd` (node in group `day_night`). Signals: `night_fell`, `blood_moon`, `moon_calmed`, `dawn`.

- Clock: `time` in hours since midnight of day 1, `day`, `is_night`, `is_blood_moon`. Real minutes per half-day set in `Economy.DAY_MINUTES/NIGHT_MINUTES` (8 + 8).
- Phases: sunrise 06:00, sunset 18:00 (`night_fell`, full moon), **19:00 blood moon** (`blood_moon`: intruders spawn, suspense music), 06:00 `dawn` (night report -> day report -> shop -> new day).
- `_advance(hours)` moves the clock and fires every event hour it passed (`_fire`), so skipping time never skips events. Same code serves "skip day/night" (`_skip_rate`, `_skip_day_rate`) and the Training-shift dusk (`_dusk_rate`).
- **Training shift (day 1) trick:** the day holds at 17:00 (`DAY_HOLD`) until the generator is fixed *and* the photo task is done; fixing it triggers a short dusk. Teaches the core loop as a tutorial without a separate mode.
- Visuals: custom sky shader `assets/sky/day_night_sky.gdshader` blends textures `01_full_moon_night.png` and `02_blood_moon.png` (`_set_blood(to, seconds)` tweens a uniform). Sun energy, fog (thin volumetric fog at night shows lamp cones) and glow are driven from `phase_progress()`; the sky's reflection is only re-rendered a few times a second.
- `_pan_to_moon()`: first night only, the player's camera is turned to the moon and control returned (cinematic beat).
- `end_blood_moon()`: when the last intruder dies, the moon returns to normal (`moon_calmed`) and chase music fades.
- Debug: F8 skips an hour.
- Loading: `_restore(data)` puts the player back and, if saved at night, replays tonight's events (workers hide, intruders come in) with `restoring = true` so the day report doesn't pop.

**Gotcha:** the clock must be "event-hour based", not "frame based", or fast-forward breaks. Keep a `restoring` flag for any system that fires reports.

---

## 4. Generators and power

**Files:** `world/generator.gd`, `world/park_lights.gd`, `world/light_switch.gd`, `game.gd` (`ride_has_power`), `economy.gd` (`GENERATOR1_RIDES`, `GENERATOR3_RIDES`, prices).

- Three generators (`@export var index`): #1 behind the galpao (lamps, PC, Carrossel), #2 bought in shop (shop rides), #3 bought, on the Zone 2 pad (zone lamps + Haunted House). Created in code by `park_additions.gd` at `Marker3D` spots.
- **They break every morning** and intruders smash them at night (`smash_spot()`, `take_hit()`, `break_down()`); to fix: hold the wrench, E -> `_fix()` with clank sounds, then it hums, shakes slightly, and an indicator light goes red/green.
- State lives in `Game` (`generator_fixed`, `generator2_fixed`, ...) and **`Game.generator_changed` / `power_changed`** are the only coupling. Anything electric subscribes.
- `park_lights.gd`: gives every node named `Lamp_*` under the Lamps node a downward `SpotLight`/`OmniLight` plus a glowing bulb; they switch on one by one with a flicker and relay clunk. `Lamp_Z2_*` run on Generator 3. A light with its wall switch off stays off.
- **Rule (author's standing design rule): no generator power = no light.** Gate any new light/switch/ride on the power signal.
- `Game.ride_has_power(ride)`: Gen1 rides need `generator_fixed`; Gen3 rides need `generator3 && generator3_fixed && owned`; others need `generator2 && generator2_fixed && ride in rides_started` (started in the Ride Manager) and the ride's power bought.

**Pattern to reuse:** a single boolean-per-source in the autoload + one "changed" signal + consumers that re-evaluate on signal. Add "wreckable" by giving the source `take_hit()` and letting enemies target `smash_spot()`.

---

## 5. Rides and the Ride Manager PC app

**Files:** `world/rides/ride_base.gd`, `ride_seat.gd`, `ride_setup.gd`, `ride_kit.gd`, `track_train.gd`, `bumper_cars.gd`, `chair_swings`/`trenzinho.gd`/`aviaozinho.gd`, `haunted_house.gd`, `ride_animator.gd`, `pirate_trap.gd`, `ui/ride_manager.gd`, `ui/pc_desktop.gd`, `world/old_pc.gd`.

**Ride model.** Every ride is a node in group `ride` placed under a `RideAreas/<Name>` node in the map (the area has a `Floor` used for size/centre). `ride_base.gd` gives:
- `set_powered(on, instant)`, `is_powered()`, `speed()` (0..1 ramp over `ramp_seconds`).
- RollerCoaster-Tycoon style cycle: run `run_seconds` (40), stop `load_seconds` (12) so riders board; `loading_started` signal; `can_board()`, `free_seats()`.
- `tick_ride(delta)` is called from the subclass `_process` and returns how far the ride advanced this frame.
- `nearest(tree, at, reach)` static helper.
`ride_animator.gd` is the cheap path for *imported* models: loops the model's animation and/or swings named parts around a pivot (pirate ship), and auto-adds seats to moving parts.

**Seats.** `ride_seat.gd` is a `Node3D` child of a moving part; whoever sits (player or visitor) copies its global transform each physics frame. `interact()` toggles on/off, only while the ride is loading. `rider_feet()`/`exit_point()` place you. Visitors use the same seats (see section 9). **Every ride is rideable** (design rule from the author).

**Procedural rides.** `ride_setup.gd` `setup(areas)` walks the map's `RideAreas` and, for areas with no model, attaches a script that builds the ride from `ride_kit.gd` primitives (faded fairground colors, 128px horror textures so the PSX shader treats them like everything else). `bumper_cars.gd` has a lever: toggle auto-driving vs. player drives. `haunted_house.gd` (670 lines): walk-in dark ride modelled on a real park haunt, boarded and FECHADO until bought, built in code, powered by Generator 3. `add_haunted_house(areas, spot, always_on)` places it (the debug map uses `always_on`).

**Pirate ship as trap** (`pirate_trap.gd`): hull gets an `AnimatableBody3D` on the swing pivot; at night, while running, it exposes `lure_point()` that intruders path to; on contact `_hit(who, velocity, at)` knocks bodies along the hull's motion with force proportional to its speed (fast = ragdoll kill). Constants `SHIP_*` in `economy.gd`.

**Ride Manager (`ui/ride_manager.gd`, 377 lines).** A fake DOS prompt in an XP-style window inside the maintenance-room PC (`pc_desktop.gd`, opened by `old_pc.gd`). Left: command line with history (Up/Down); right: "Notes" from the last operator. The player *types*:
```
start ride --spot <plaque number> --power <gen1/gen2>
```
`_on_submit` -> `_start_command(words)` -> `_start(spot, power)` validates (ride owned? generator bought and fixed? right generator named? spot number is on a plaque by the ride) and on success appends to `Game.rides_started`. After one success `/spot<n>` re-runs it (`Game.ride_shortcuts`). `status` lists rides. Rides trip every morning so this is a nightly chore. Pattern: **diegetic command-line puzzle** - validation messages teach the syntax; Notes only hint.

**Gotchas:** keep ride numbering in `Economy.RIDE_SPOTS` (+ `STAND_SPOTS`, `ZONE2_SPOTS`) so plaques, manager and shop agree. Code-built rides need `solid()` collision boxes from `ride_kit`.

---

## 6. Economy, reports and shop

**Files:** `economy.gd`, `ui/night_report.gd`, `ui/day_report.gd`, `ui/shop.gd`, `world/food_stand.gd`.

**Loop:** day (guests, rides, trash) -> sunset: `day_report` computes complaints, rating, ticket cut (stored as pending) -> night (intruders) -> dawn: `night_report` (generators, kills, workers saved/dead, pay) -> `day_report.open_pending(after)` -> `shop` -> new day.

**Performance score (0-1)** = weights: rides running 0.40, workers alive 0.25, no intruders left 0.15, clean park 0.20 (`PERFORMANCE_*`). `RATING_STEPS` maps score to 1-5 stars; **yesterday's stars multiply today's guest count** (`VISITORS_RATING_MULT`) on top of `VISITORS_BASE_BY_DAY`. This is the whole difficulty/feedback spiral in ~10 constants.

**Money:** guests pay `TICKET_PRICE`; the player gets `PG_CUT` of it, minus `COMPLAINT_FINE` per complaint. Complaint sources: rides off, dead workers, intruders left, trash, random. Reviews text (`_write_reviews`) is generated from what actually went wrong, so the Reviews app is truthful feedback.

**Shop (`shop.gd`):** same 3D-carousel layout as the inventory. `_list()` returns entries `{title, desc, price, blocked, model, bought, instead}`; `blocked` is a reason string (e.g. needs Generator 2) and `bought` a `Callable` that mutates `Game`. Add a product = add one dictionary. Sells generators, ride power, rides (bumper cars $500, haunted house $700), cameras, Camera Watcher app, hot dog stands (choose spot first, pay after), trash bags, medkits, painter. Opens after the night report ("START THE DAY") and anytime from the phone.

**Gotcha:** pay on *success of placement* (stand: pick spot first, then charge).

---

## 7. Phone and its apps

**Files:** `ui/phone.gd` (1065 lines), `staff_app.gd`, `reviews_app.gd`, `black_market.gd`, `camera_viewer.gd`, `xp_window.gd`, `photo_subjects.gd`, `world/photographable.gd`.

- A pixel-art flip phone slides up from the bottom (Up arrow or pause menu); mouse cursor appears; home screen is an XP desktop with app icons (`APPS` list; "cams" appears only after buying Camera Watcher). Unread texts badge via `Game.unread_changed`; texts arrive via `Game.text_received(from, text)` with a beep and open straight on Messages.
- **Messages:** scripted P.G. conversation; a table maps what you can text him (each once) to his answers, one of which delivers the Black Market code.
- **Camera app + investigation:** crosshair raycast (range const) to a `Photographable` node whose `id` indexes `photo_subjects.gd` (`result`, `explanation`, optional evidence `image`, `clue` flag). Many nodes share one id (every bench = `park_bench`). Photos go to `Game.photos` and the inventory Photos tab (flagged clues). A photo task from P.G. gates the Training shift.
- **Staff app:** list of workers with job/health/state, orders (janitor: keep this spot clean, clean the blood; painter: which ride to repaint tonight). Hiring the painter lives here.
- **Reviews app:** star rating + review texts (`Game.reviews`).
- **BMA (black_market.gd):** locked until the code is typed; then sells melee weapons, guns and ammo from `Economy.BLACK_MARKET`; purchases go straight into inventory.
- Reusable `xp_window.gd` draws XP-style title bar/window chrome; the Ride Manager and PC reuse it.

**Pattern:** each app is a `Control` subclass with `_fill()` building rows; phone owns navigation and soft keys (left click / right click = Back). Add an app = add an entry to `APPS` + a script.

---

## 8. Pause, save and load

**Files:** `ui/pause_menu.gd`, `ui/save_menu.gd`, `game.gd` (`save_game`, `load_game`, `autosave`, `list_saves`, `delete_save`), `day_night.gd` (`_restore`).

- Esc -> pause menu (Resume, Phone, Save, Load, Options, Quit to Menu). Saving/loading only from here (and load from the main menu). The same `options_panel` is reused by menu, inventory and pause.
- **Save format:** a `Dictionary` written with `FileAccess.store_var` to `user://saves/*.sav` (`save_<unix>_<rand>.sav`, autosaves `auto_<kind>.sav`). Keys: `version` (`SAVE_VERSION = 1`), `label`, `auto`, `unix`, `day`, `time`, `day_name`, `clock_text`, `game` (all vars named in the `SAVED_VARS` const), `photos` (PNG bytes + day), `player` (position, yaw, pitch, health). Blood stains are gathered via the `"blood"` group (`to_save()`).
- **The `SAVED_VARS` pattern is the key reuse:** one const list of variable names on the autoload; save loops `state[v] = get(v)`, load loops `set(v, state[v])` (Arrays use `assign()` to keep typing). Add a persistent variable = add its name to the list. Missing keys on old saves are skipped, so new fields don't break old saves.
- **Load flow:** `load_game(path)` restores vars, stores `pending_load`, changes scene to the park; `day_night._restore` consumes `pending_load` to move the player and replay the night. Anything that spawns by itself (workers, intruders) must read the clock, not assume a fresh day.
- Autosaves at morning and when a generator is fixed (small corner note, fades).
- `danger()` returns a warning string (being chased, <30% health, intruders out) - the save screen shows it in red but still allows saving. Two-click confirm for overwrite/delete (`_confirm`).

**Gotchas:** `store_var` is not forward-compatible with removed variables; use `version` for migrations. Don't save `Object` references - save ids/names. Reset `cheats_unlocked` on `new_game()`.

---

## 9. Visitors, trash and the janitor

**Files:** `world/visitors.gd` (manager, group `visitor_manager`), `world/visitor.gd`, `world/trash.gd`, `trash_piece.gd`, `trash_drop.gd`, `street_furniture.gd`, `world/janitor.gd`.

- **Count per day:** `visitors.count_for_day(day)` (static) from `Economy.VISITORS_BASE_BY_DAY` x rating multiplier (+ open hot dog stands). Arrival times are spread over 06:30-11:00 (`_plan_day`), they leave from 16:30, all gone by sunset. On a mid-day load, those who'd have arrived are spawned already inside.
- **Cap rendered:** at most `VISITORS_SHOWN_MAX` (70) bodies exist; the rest only count for money.
- **Walkway graph:** the map has a `Walkways` node of boxes; `visitors.gd` samples points along each path, joins nearby points (including across paths), and `route(from, to)` returns a `PackedVector3Array` (onto nearest walkway, along it, off at the destination). Falls back to straight lines if the map has none. No NavMesh needed for guests.
- **Visitor behavior (`visitor.gd`):** pick `random_spot()` (a built ride, a stand with stock, a bench, anywhere) -> walk -> idle -> next; drops trash from an allowance; at a running ride waits until it loads, takes a free `ride_seat`, rides one go-round, gets off. **No collision** (scenery, never blocks workers/player). Models are baked `.scn` with "Idle"/"Walk" in a `worker` animation library; kids = adults scaled.
- **Trash:** guests call `trash.drop_at(pos)` (snapped to the navmesh), `TRASH_PER_VISITOR = 1.5`. Walk over a piece or E to pick up (capacity = bag: `TRASH_CARRY` 5, upgrades `TRASH_BAGS`), E on a trash can/dumpster to empty. Janitor picks one every `JANITOR_PICKUP_SECONDS`. Leftover trash at closing = complaints. A spawned `pickup` over nothing was a bug when buried tires were counted as trash - only count real pieces.
- **Food stands:** `food_stand.gd` + per-spot `hotdog_stock`, `stand_vendors`, boxes delivered to the parking lot (`delivery_box.gd`) that the player carries to stands. Stand model is baked from a pack (`tools/props/bake_taco_stand.gd`), has a `VendorSpot` marker.

---

## 10. Workers (janitor, technician)

**Files:** `world/worker.gd` (base), `janitor.gd`, `technician.gd`, `broom_model.gd`, `ui/staff_app.gd`.

- `worker.gd` is a small state machine (WORK, HIDE/FLEE, FOLLOW, SAFE, DOWN, DEAD): by day does a job, `E` opens a dialogue (opening lines the first time, then a list of questions, each answered once; asked questions saved in `Game.talked` as `"Name|question"`, daily opener `"Name@day"`).
- Subclasses override hooks: `_opening()`, `_topics()` (list of `[question, answer]`), `_lore_key()`, `_start_work()`, `_work(delta)`, `_after_talk(asked)`, `start_new_day()`. Add a worker type = extend and override ~4 methods.
- **Night rules:** when the blood moon starts they run and hide; E on a hiding worker makes him follow (stays `FOLLOW_DISTANCE` behind); get him into the maintenance room and he stays safe till morning (pay per worker saved). Intruders notice workers in the open and stalk them (`killer.State.STALK`).
- **Health:** first drop to half -> he goes down and bleeds out in `BLEED_OUT_SECONDS` (120) unless healed with a medkit; second time nothing saves him. Signals `rescued`, `died`. Hit-today flag feeds a fee in the night report.
- **Janitor:** pushes a procedural broom along paths (`_next_stretch` picks the next stretch), broom follows the palm bones of the "Sweep" clip (`_process` + `_palm(side)`); can be ordered to a spot or to scrub blood (`_clean_blood` walks pool to pool). **Technician:** kneels by the maintenance room, wrench attached to the `mixamorig_RightHand` bone; on day 1 nags about the generator.
- Models are Mixamo-rigged PSX characters with Quaternius UAL clips retargeted at bake time (section 17).

---

## 11. Intruders and killer AI

**Files:** `world/intruders.gd` (manager, group `intruders`), `killer.gd` (957 lines, group `killer`), `villain.gd` (panda boss), `world/morning_bodies.gd`.

- **Navmesh baked at runtime:** `intruders._bake_navmesh()` collects *static collision only* (`_collect_colliders`: CSG with collision + StaticBody shapes) into `NavigationMeshSourceGeometryData3D` and calls `NavigationServer3D.bake_from_source_geometry_data_async`. Avoids reading back from the GPU and works with CSG-built maps. Guests/trash reuse it ("waits for the navmesh").
- **Spawning:** on `blood_moon`, `spawn()` brings in N killers (more each night, `INTRUDERS_BY_NIGHT`) at park edges; the Pigman variant has its own model/sound. 40% chance from day 2 of an **ambusher** waiting in the bathroom (`AMBUSH_*`). At dawn `send_away()`.
- **State machine (`killer.State`):** `IDLE, CHASE, ATTACK, HIT, DEAD, ROAM, LEAVE, SABOTAGE, STALK`; attack sub-phases `WINDUP, HOLD, STRIKE, RECOVER` (a freeze at the top of the windup is the **telegraph**). Per-attack timings are tables of (windup peak, impact, cut-off seconds).
- **Perception:** intruders roam with a flashlight (a cone, `flashlight range/angle`); if the beam hits the player (or they are heard within a short radius) `intruders.player_found()` tells *everyone*, who then hunt together (`hunt_started`), re-planning paths every `REPATH` seconds with a `NavigationAgent3D`. Losing them by breaking line of sight is possible (polish pass).
- **Roles:** while a generator runs, one intruder gets `sabotage()` / `_send_saboteur_to(gen, alive)` and smashes it (`SABOTAGE_SWINGS` hits), but only if another is left to chase the player. A roaming one that sees a worker goes `STALK`. Once the player owns a gun, **armed** intruders shoot from range (never at workers).
- **Pirate ship lure:** killers ask `lure_point()` of group `lure` members.
- **Ending the night:** `_on_killer_died` -> when none alive: chase music stops, `day_night.end_blood_moon()`. `morning_bodies.play(clock)` lines up the bodies the first morning and P.G. talks; later mornings they just vanish with a different text each day.
- Group `being_chased()` helper in `Game`: any killer in CHASE/ATTACK (used to block skipping, the shop, saving warnings).

**Gotchas:** intruders spawning outside the fence came from spawn points not snapped to the navmesh (use `NavigationServer3D.map_get_closest_point`); an invisible wall at the 2nd Zone was a collision box without a visible fence. Always snap spawn points and match collision to visuals.

---

## 12. Combat, weapons and blood FX

**Files:** `player.gd` (melee/guns), `killer.gd` (damage/ragdoll), `blood_fx.gd` (`class_name BloodFx`), `world/blood_stain.gd`, `severed_arm.gd`, `world/gun_model.gd`, `ui/high_fx.gd`, `world/vape_pen.gd`.

- **Melee:** clips in `assets/fp/hammer_swings.tres` played in order while you keep clicking (combo window), hit-stop (`freeze` a few frames on connect), screen motion blur. The wrench and black-market melee weapons reuse the same swing, holding via the `hold` points in `ITEMS`.
- **Damage model:** head hits do extra (head hitbox = a sphere on physics layer reserved for heads, checked first); 2 head hits / 4 body hits kill a killer. Player has 100 HP; below a fraction the left arm comes off (`arm_lost`, `severed_arm.tscn` can be picked up with E), after which swings do reduced damage.
- **Guns:** `Game.ammo` (spare) and `Game.loaded` (in the gun) per gun, `ammo_changed`, reload with R, recoil kick on the viewmodel, muzzle flash, `cheat_ammo` toggle. Armed intruders only appear after `Game.gun_day` is set (night you first had a gun).
- **Medkits:** H heals `MEDKIT_HEAL`, E on a downed worker saves him.
- **Death/ragdoll:** at 0 HP killers go `DEAD` and ragdoll; knockback from the ship is a real ragdoll via velocity.
- **Blood (`BloodFx` static helpers):** `burst(parent, at, size)` = billboard sprite playing a 4x4 flipbook (`blood_burst_4x4.png`) once then freeing itself; `pool(parent, at, size)` = a spreading `Decal` projected on the floor that stays until cleaned. `BloodStain.scrub(amount)` reduces it (player with the broom, janitor on order); stains are saved/restored (`to_save()`, `BloodFx.restore`). Guests complain about leftover blood.
- **Broom:** held in both fists (`broom_model.gd`, procedural), scrubbing sweeps a width and cleans per second of contact.
- **Vape pen** (`vape_pen.gd` + `high_fx.gd`): pickup that applies a 10 s screen-warp "high" shader.

---

## 13. Cameras and investigation

- **Security cameras:** `Economy.CAMERAS` dictionary {name, pole position, watched point}; a `Marker3D` named `Cam_<id>` in the map overrides. `cameras.gd` puts up the ones in `Game.cameras` (start: entrance, generator; rest bought) and opens `camera_viewer.gd`. Viewer: full-screen grainy green night-vision, REC light, clock, A/D switch camera. Opened from the PC icon, or anywhere with C once the Camera Watcher app is owned.
- **Damage:** an intruder within `CAMERA_DANGER_RANGE` for `CAMERA_BREAK_SECONDS` breaks the camera (`security_camera.gd`: a 0-1 "danger" value drives static; then NO SIGNAL). Fix with the wrench on the junction box (`interact`/`use_item`).
- **Investigation:** photo mode of the phone (section 7) + `Photographable` nodes; discoveries counted by `clue` flag. Ordinary things get plain text, clues hint at the truth.

---

## 14. Cheats and debug map

- **Cheats** are in the Options panel (`options_panel._open_cheats`): a password box (password constant in `game.gd`); after unlocking, toggles built with `_cheat_toggle(title, flag, after)` which just flip a bool on `Game` (`cheat_ammo`, `cheat_god`, ...). Rules: the password is asked **every time** Cheats opens; `cheats_unlocked` resets on leaving the panel and on `new_game()`; cheat flags are not saved. A diegetic hint (a Dr. Enéas 1992 note) sits in the cabinet.
- To add a cheat: add `var cheat_x := false` on `Game`, add `_cheat_toggle("Name", "cheat_x")`, and check `Game.cheat_x` where the rule applies.
- **Debug map** (`scenes/debug_map.tscn`, `scripts/debug_map.gd`): a small test level with the player armed (`starts_armed`), a spawn menu, every ride powered (`add_haunted_house(..., always_on=true)`), and F8 time skip. Keep one of these for every game: fast iteration beats loading the whole park.

---

## 15. Audio

**File:** `world/park_audio.gd`. Buses: Master, Music, **Ambience** (own slider in Options). 
- Wind loop everywhere, stronger at night; background beds crossfade between `forest_day`, `forest_night`, `inside_day`, `inside_night` depending on whether the player stands over an "indoor floor" box (`indoor_floor_paths`).
- Each ride has a looping `AudioStreamPlayer3D` at its centre (table `Ride node -> [sound, pitch, volume dB]`), volume driven by power/speed (`_update_rides`).
- Blood moon: `suspense_loop` creeps in and "Chase 3" plays (`_on_blood_moon`); fades out on `moon_calmed`/`dawn` with a tween helper `_fade(player, prop, value, seconds)`.
- Generator: start sound, looping hum, break stinger; wrench clanks (2 variants); phone SMS beep; title BGM from `Game` plays low (`AMBIENT_MUSIC_DB`) once you have the cabinet key.
- Footsteps by surface (player), growl/pigman sound optional (`killer` loads if the file exists).

**Gotcha:** all reactive audio subscribes to day_night/Game signals; don't poll.

---

## 16. Look: PSX shader, minimap, UI style

- **PSX look (`psx_look.gd`):** replaces every `StandardMaterial3D` in the scene with a generated `ShaderMaterial` (vertex snapping to a coarse screen grid for the wobble, affine-ish look) and adds a full-screen pixelate + dither pass. A `child_entered`-style hook (`_on_node_added`) converts nodes added later; `_supported()` leaves unsupported materials alone. Graphics presets and FPS counter in Options.
- **Minimap (`minimap.gd`):** one top-down snapshot taken at load (high camera in daylight, a few frames to let materials finish, saved as an `ImageTexture`, camera freed). The map is a rotated crop of that texture around the player; icons from a table `[world pos, kind, label]`; workers/intruders/generators drawn live; same texture used by the inventory's full map. Unlocked by carrying the Park Map item.
- **UI style:** one font (VT323), `ui_style.gd` holds the palette/styleboxes; computer/phone UIs use a Windows XP look (`xp_window.gd`); Windows-arrow cursor drawn from an ASCII bitmap in `game.gd`.
- **Map dressing in code:** `park_additions.gd` (generators, plaques, props), `park_dressing.gd` (Portuguese signs, decals, clutter) and `forest_ring.gd` (a `MultiMesh` ring of ~1900 trees) add detail without editing the large `.tscn`. Editing a 480 KB scene by text was only done once, via a one-shot Python script (`tools/map/build_zone2.py`) after a backup.

---

## 17. Asset import and bake tools

All under `tools/`, run **headless from a copy of the project** with source packs unpacked into `res://zz_src/`:
```
godot --headless --import
godot --headless --script res://tools/workers/bake_workers.gd
```
- `tools/workers/bake_workers.gd`: takes a Mixamo-rigged PSX character FBX + texture, scales to a height in metres, and adds an `AnimationPlayer` with a `worker` library of Quaternius UAL clips **retargeted** to that skeleton; bakes everything (meshes, textures) into a self-contained `.scn` so the game needs no source files. `ONLY=a,b` env var builds a subset. `fix_worker_anims.gd` fixes rest pose/arm issues on new bakes only (never re-run on old ones). `test_workers.gd/.tscn` previews them.
- `tools/people/bake_people.gd`: same for visitors (men, women, kids as shrunk adults) and the Pigman (killer clips copied onto his skeleton, shovel in hand). `fix_visitor_anims.gd`: arm fix + Sit clip.
- `tools/props/bake_taco_stand.gd`: cuts one stand out of a big pack into `taco_stand.scn` with a `VendorSpot` marker. `make_bilheteria_mural.py` paints the ticket-booth mural.
- `tools/brand/make_icon.py`: window/itch icon and cover.
- Pack FBX files often don't link textures: `street_furniture.gd` applies the PNG at runtime.
- Export: `export_presets.cfg` (Windows; web/phone build still open).

**Tips:** bake once into `.scn`, commit baked files; keep sources out of the shipped project. Retarget by bone *name* (Mixamo `mixamorig_*`) so any clip library fits any character.

---

## 18. Reuse checklist for a new game

1. Create the autoload `Game` with signals + `SAVED_VARS` + `save_game/load_game`. Add `economy.gd` consts file.
2. Copy `day_night.gd` pattern: hour-event clock + signals (`night_fell`, `dawn`, ...) and have everything else subscribe.
3. Use duck-typed `interact/prompt/use_item` + HUD crosshair prompt.
4. Build menus in code; one `ui_style.gd`; menus `PROCESS_MODE_ALWAYS` and guarded by `_can_open()`.
5. Power/resource chains: boolean in `Game` + `changed` signal.
6. Enemies: `NavigationAgent3D` + a runtime-baked navmesh from static collision; an `intruders` manager that broadcasts "player found".
7. Characters: bake `.scn` with retargeted animation libraries (tools/).
8. Keep a debug map and F-key time skip; keep a `.gdignore` backup folder.
9. Put balance in constants, flavor in `story_texts.gd`, and write `##` comments explaining *who makes this node and what it reacts to*.
10. Design rules to keep (author's): no power = no light; computer/phone UIs in XP style; every ride rideable.
