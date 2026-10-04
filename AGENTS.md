# Apex Rush — Agent Guide

Top-down 2D arcade racing game. Local 2-player, laps + positions HUD, AI rivals, powerups
(nitro / oil / shield), track props (kerbs, cones, barriers, marshals, trees).

- **Engine:** Godot **4.7.2** (Forward+), GDScript only
- **Main scene:** `scenes/menu/main_menu.tscn` (UID `uid://bb8k3si8225ph`)
- **Autoload:** `GameManager` → `autoload/game_manager.gd` (UID `uid://cekeau5ms6uvd`)
- **Viewport:** 1280x720, `canvas_items` stretch with integer scaling, nearest-neighbour textures
- **Renderer:** d3d12 (Windows)

## Read before working

| Doc | What it answers |
|---|---|
| `docs/architecture.md` | Where does this file go? What references what? |
| `docs/conventions.md` | Naming, coding and scene rules |
| `docs/workflow.md` | How do I run, test and verify changes? |
| `docs/backlog.md` | Known follow-up work |
| `docs/session-log.md` | What happened last session / current state |

## Hard rules (non-negotiable)

1. **Never edit anything inside `.godot/`** — generated cache, git-ignored.
2. **After ANY file move, rename or delete, run:**
   `powershell -ExecutionPolicy Bypass -File tools/check_references.ps1`
   It must print `OK - all references resolve`. Fix every `MISSING ->` line before moving on.
3. **Never move or rename a resource on its own.** Godot resolves assets by UID (`.uid` / `.import`
   sidecars) **and** by `res://` path text inside `.tscn` / `.gd`. Move the asset **together with its
   `.import` / `.uid` sidecar**, keep the original `uid=` value, and update every `res://` reference.
4. **Everything is `snake_case`** — folders, scripts, scenes, assets. No spaces, no parentheses,
   no `NewCar1.png`.
5. **Scenes and their scripts are colocated and share a name** (`player_car.tscn` + `player_car.gd`).
6. **New files go where `docs/architecture.md` says** — never in the project root.
7. **Do not add autoloads.** `GameManager` is the only one; adding another requires updating
   `docs/architecture.md` with the justification.
8. **Do not scatter `res://` scene paths around the code.** The next race scene to load is carried by
   `GameManager.target_scene_path`.
9. **A change is "done" only when all four checks in `docs/workflow.md` pass** (reference check, headless
   import, per-scene sweep, runtime boot).
10. **Commits:** one logical change per commit, conventional prefixes (`docs:`, `chore:`, `refactor:`,
    `feat:`, `fix:`). Never mix a refactor with a feature.
11. **Keep the docs alive:** update `docs/architecture.md` when the structure changes, append an entry to
    `docs/session-log.md` at the end of every session (keep last ~3, older history lives in git).

## Quick map

```
autoload/   scenes/{menu,race,pickups,effects,results}/   assets/{sprites/{cars,track,ui,powerups,effects},fonts,audio,source}/   docs/   tools/
```
