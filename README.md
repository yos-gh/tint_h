# TINT horizontal

A physics-based falling-block puzzle prototype about stacking soft tetrominoes vertically in a wide field while keeping the pile near the center.

[Play TINT horizontal in your browser](https://yos-gh.github.io/tint_h/)

## Prototype rules

- A column clears when stones form a continuous vertical path from the green clear line to the curved floor.
- The required height is approximately nine stones, with extra space above it for controlling incoming pieces.
- The game ends when stones remain beyond either red deadline for five continuous seconds.
- Clearing another column within one second increases the chain multiplier. Clearing multiple columns together increases it by the number of columns cleared.
- Field dimensions, deadline positions, and scoring values are provisional prototype settings.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | `A` / `D` or arrow keys | D-pad or left stick |
| Soft drop | `S` or down arrow | D-pad down or left stick down |
| Rotate counterclockwise | `N` | `A` or `X` |
| Rotate clockwise | `M` | `B` or `Y` |
| Restart | `R` | — |

## Run locally

TINT horizontal requires Godot 4.7 or later. Open `project.godot` in Godot or run:

```powershell
Godot.exe --path .
```

## Build for the Web

Install the official export templates matching your Godot version, then export the game to `web/game`:

```powershell
Godot_console.exe --headless --path . --export-release Web web/game/index.html
```

The prototype reuses the soft-block physics, curved bowl, controls, and touchscreen interface from the original [TINT](https://github.com/yos-gh/tint).

## Error monitoring

The browser build includes the official Sentry SDK for Godot. Runtime errors and crashes are reported to Sentry using the public DSN configured in `project.godot`.
