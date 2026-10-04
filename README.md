# RoHoops

A skill-focused Roblox basketball game: simple controls, difficult execution.

The current build is a movement and shooting test on a single hoop: a plain floor, a backboard and a rim.

## Setup

Tools are pinned with [Rokit](https://github.com/rojo-rbx/rokit) in `rokit.toml` (Rojo, Selene, StyLua, Lune).

```sh
rokit install
mkdir -p build && rojo build -o build/RoHoops.rbxl   # open this file in Studio
rojo serve                                           # then connect from the Rojo Studio plugin
```

Start from the built place rather than a Studio template, so there's no Baseplate or extra SpawnLocation.

## Controls

| Input | Action |
|---|---|
| `W A S D` / arrows | Move (relative to the screen, so up is always toward the rim) |
| `Shift` | Run |
| `E` (hold, release) | Shoot / finish. Release when the meter reaches the white tick |

What `E` does depends on where you are and how you're moving when you press it:

| Context | Shot |
|---|---|
| Standing still | Jump shot |
| Moving toward the rim | Pull-up |
| Walking away from the rim | Fadeaway |
| Running away from the rim | Step-back |
| Moving mostly sideways | Side shot |
| Within 8 ft, moving toward the rim | Layup |
| Within 8 ft, otherwise | Close shot |

Early releases fall short and late ones go long. Perfect releases (inside the green zone) go in. Every shot gets harder with distance past 12 ft and with harder shot types.

## Live tuning

In Studio, every number in `Config/Movement`, `Config/Camera`, `Config/Shooting` and `Config/Ball` appears as an attribute under `ReplicatedStorage > Tuning` while playing; switch the Explorer to the **client** view to edit them. Changes apply immediately but aren't saved, so copy values you like back into the config files. `Workspace.Gravity` (55) controls both jump height and ball flight.

## Layout

```
src/
  shared/              -> ReplicatedStorage.Shared
    Config/            tuning values (Court, Movement, Camera, Shooting, Ball)
    MovementMath.luau  pure acceleration / smoothing math
    ShotMath.luau      pure shot type, timing grade, aim error and arc math
    Tunable.luau       Studio-only live tuning
  server/              -> ServerScriptService.Server
    HoopBuilder.luau   floor, backboard, rim, spawn
    CollisionGroups.luau
  client/              -> StarterPlayerScripts.Client
    CharacterRef.luau  current character tracking
    Controllers/       Input, Movement, Camera, Ball, Shot, Hud
tests/                 Lune specs for the pure modules
```

## Checks

```sh
lune run tests/run          # unit tests
selene src tests            # lint
stylua --check src tests    # formatting
```
