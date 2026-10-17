# Matinha Theme Park Horror Game

Godot 4.7 project. Open the folder in Godot and press F5 to walk around the park.

Controls: WASD to move, mouse to look, Shift to run, Space to jump, Esc to free the mouse (click to recapture).

## Map

`scenes/park_map.tscn` is the first section of the park, laid out from snow's sketch (about 1 px = 0.12 m) and dressed with the packs in `assets/` (credits in `assets/CREDITS.md`):

- Parking lot with its U-shaped lane, parked cars, lamp posts and a gate across the exit.
- Brick entrance wall with the two yellow arches and the blue wall.
- Ticket stand (retro store kit) and the bathrooms building, with a PSX bathroom interior you can walk into from the west side.
- Fenced, textured areas for the rocking pirate ship, chair swings, Minhocão coaster and bumper cars. No rides are built or scripted yet.
- Metal fence around the park and lot, bushes along the inside, forest outside.

Everything you can bump into has collision, and invisible walls keep you inside the park and the parking lot.
