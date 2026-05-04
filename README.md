# Worm Game - Zig + raylib

A classic worm/snake game implemented in Zig using raylib, featuring an autoplay mode with BFS pathfinding.

## Prerequisites (FreeBSD)

Install the required dependencies using pkg:

```sh
sudo pkg install zig raylib
```

This will install:
- **Zig** - The Zig compiler and build system
- **raylib** - Simple and easy-to-use library for game development
- Required system libraries (automatically pulled in as dependencies):
  - math library (libm)
  - pthread
  - dl
  - rt

The project is configured to find raylib headers in `/usr/local/include` and libraries in `/usr/local/lib`, which is the standard location on FreeBSD.

## Building and Running

To compile and run the game in optimized release mode:

```sh
cd worm-raylib
zig build -Doptimize=ReleaseFast run
```

### Other Build Options

```sh
# Debug build (with runtime safety checks)
zig build -Doptimize=Debug run

# Fast release build (as shown above)
zig build -Doptimize=ReleaseFast run

# Smallest release build (optimized for size)
zig build -Doptimize=ReleaseSmall run

# Just build without running
zig build -Doptimize=ReleaseFast
```

The compiled binary will be located at `zig-out/bin/worm-game`.

## How to Play

### Controls

| Key | Action |
|-----|--------|
| **Arrow Keys** | Move the worm (Up/Down/Left/Right) |
| **A** | Toggle autoplay mode |
| **Space** | Pause/Resume the game |
| **R** | Restart after game over |
| **ESC** | Quit the game |

### Gameplay

1. **Objective**: Control the worm to eat the red food squares that appear on the grid.

2. **Growing**: Each time you eat food, the worm grows longer and your score increases.

3. **Movement**: The worm moves continuously. You can change direction using the arrow keys, but you cannot reverse direction 180 degrees (e.g., if moving right, you can't immediately go left).

4. **Walls**: The game features wrap-around - when the worm exits one side of the screen, it reappears on the opposite side.

5. **Game Over**: The game ends if the worm collides with itself.

6. **Autoplay Mode**: Press 'A' to enable/disable autoplay. When enabled, the game uses a BFS (Breadth-First Search) algorithm to automatically navigate the worm to food while avoiding collisions with itself.

### Scoring

- Each food eaten gives you 10 points
- The worm speeds up as your score increases (every 20 points)

## Technical Details

- **Language**: Zig (uses C import for raylib)
- **Graphics Library**: raylib
- **Grid Size**: 20x20 pixels per cell
- **Screen Resolution**: 800x700 pixels
- **Collision Detection**: O(1) using an occupancy grid
- **Autoplay AI**: BFS pathfinding with flood-fill reachability analysis
- **Data Structure**: Circular buffer (deque) for worm segments

## Project Structure

```
worm-raylib/
├── build.zig       # Zig build configuration
├── main.zig        # Game source code
└── README.md       # This file
```
