# Silly Kitty

Jam entry for **Jamference: AI Game Jam Hack 1** (theme "Cat and Robot"). Deadline **2026-10-09 07:00 UTC+3**.
Concept "Laser Lure": the player steers a hovering robot; an AI-driven cat stalks the robot, gets distracted,
flees threats and naps; lure it to its bed. Plan and acceptance criteria: `.claude/plans/main.md`.

## Hard rule: Movement Input Only (mandatory jam restriction)
- The only input actions are `move_left`, `move_right`, `move_up`, `move_down` (arrows, WASD, gamepad d-pad, left stick).
- Read input only via `Input.get_vector(...)` / `Input.is_action_*` with literal `move_*` names. Never raw keys, mouse, touch or joypad APIs.
- No buttons or clickable UI. Every `Control` uses `mouse_filter = IGNORE` and `focus_mode = NONE`. Menus are rooms you drive through; restarts are automatic.
- `tools/check_project.gd` fails validation on: input actions other than `move_*` or overridden `ui_*` actions; raw key/mouse/touch/gesture/joypad or pointer APIs, physics picking and non-`move_*` action reads in any `.gd`, `.tscn` or `.tres` (embedded scripts included); clickable Controls created in code; Controls in scenes that are not `IGNORE`/`NONE`. It is a text and scene scan, not a proof, so still review input code by hand.

## Layout
```
CLAUDE.md
.claude/plans/main.md      plan + acceptance criteria
sillykitty/                Godot 4.7.1 project (Compatibility renderer, 1280x720, canvas_items stretch, keep aspect)
  art/                     hand-authored SVG sprite parts
  audio/sfx/               generated WAV sound effects (tools/sfx.py), committed
  data/cat_tuning.tres     every cat behaviour number (CatTuning resource)
  scenes/                  robot, cat, hazards, props; scenes/levels/level_NN.tscn
  scripts/                 one script per scene type (class_name = file name in PascalCase)
tools/                     outside the Godot project, never imported or exported
  check_project.gd         restriction + strict-compile gate (run by validate.sh)
  test_gameplay.gd         headless gameplay tests (run by validate.sh)
  sfx.py                   deterministic stdlib synthesiser for every sound effect
  validate.sh              import + project check + gameplay tests + headless run
  build_web.sh             validate + web export + smoke test + itch zip
  smoke_web.mjs            Playwright (system Chrome) smoke test of the web export
  package.json, package-lock.json   pinned Playwright dev dependency
build/                     git-ignored: web export, logs, smoke screenshot, sillykitty.zip
```

## Commands (run from repo root)
`GODOT` overrides the Godot binary (default `/Applications/Godot.app/Contents/MacOS/Godot`).
- One-time tool setup: `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix tools ci` (uses installed Google Chrome).
- Validate (run after every change): `tools/validate.sh` (each Godot call is killed after `GODOT_TIMEOUT` seconds, default 300)
- Smoke test an existing export only: `npm --prefix tools run smoke` (or `node tools/smoke_web.mjs [buildDir]`, default `build/web`); screenshot goes to `build/smoke.png`. Env: `SMOKE_BOOT_TIMEOUT_MS`, `SMOKE_SETTLE_MS`.
- Release build for itch.io: `tools/build_web.sh` → `build/sillykitty.zip` (upload as HTML, "played in the browser", viewport 1280x720, SharedArrayBuffer off).
- Regenerate sound effects: `python3 tools/sfx.py` (writes `sillykitty/audio/sfx/*.wav`, byte-identical on every run).
- Run only the gameplay tests: `"$GODOT" --headless --path sillykitty --fixed-fps 60 --script "$PWD/tools/test_gameplay.gd"`.
- Logs for any failure: `build/logs/{import,check,test,run,export}.log`.

Gotchas:
- Godot exits 0 even when a `--script` fails to compile. Never trust its exit code for script runs; `validate.sh` requires the explicit `check_project: OK` / `test_gameplay: OK` lines and fails on any ERROR/WARNING in their logs.
- Quitting a script run right after freeing a playing sound reports leaked `AudioStreamPlayback` objects; `test_gameplay.gd` waits in real time before quitting.

## Gameplay architecture
- Physics layers: 1 = walls, 2 = robot, 3 (bit value 4) = cat. Robot and cat collide only with walls. Hazards are `Area2D` with `collision_layer = 0`, `collision_mask = 4`, so only the cat triggers them (the robot hovers).
- Cat brain (`scripts/cat.gd`): each physics tick scores idle, chase robot, each available distraction (group `distractions`) and each bed in range (group `goals`); the current choice gets `hysteresis`. Terminal states `FAILED` / `CLEARED` emit `failed(reason)` / `reached_goal`.
- `Level` (`scripts/level.gd`) listens to the cat, shows the banner and restarts via `reload_current_scene()` (1.6 s after a fail, 2.5 s after a clear). No input is needed to continue.
- Levels: `RoomFloor` draws the floor; border `Wall`s go under `Room`; furniture `Wall`s, the robot and the cat go under the y-sorted `Actors` node. `Wall` origin is the bottom-centre of its footprint.
- Positions of the robot, cat and props are their feet; visuals are drawn upward from there.

## GDScript conventions
- Godot 4 style guide: tabs, `snake_case` files/functions/variables, `PascalCase` nodes and `class_name`, `UPPER_SNAKE` constants, signals in past tense.
- Static typing everywhere. `project.godot` raises every default GDScript warning to **error**, so warnings fail validation (release exports skip warnings, players are unaffected). Prefix intentionally unused parameters with `_`.
- No silent failures: check results of loads, file and save operations; report failures with `push_error` including the path or node involved.

## Art pipeline
- Sprites are hand-authored SVG in `sillykitty/art/`, imported natively by Godot. Characters are built from separate parts animated procedurally in-engine; no sprite sheets.
- Style: flat fills, `#3B2C35` ink outline 3px (2.5px on small parts) with round joins, soft highlights, shadows from `shadow.svg`.
- Cat parts (side view facing right, flip for left): `cat_body`, `cat_head`, `cat_ear` (x2), `cat_tail` (pivot at the tail base, bottom-right), `cat_paw` (x4).
- Robot parts (front view): `robot_body`, `robot_face`, `robot_antenna` (pivot at the stem base), `robot_thruster`, plus `shadow`.
- Props: `puddle` (hazard), `cat_bed` (goal), `yarn` (distraction). Walls and floors are drawn in code (`wall.gd`, `room_floor.gd`).

### Palette
| Token | Hex | Use |
|---|---|---|
| ink | `#3B2C35` | outlines, eyes, shadow (22% opacity) |
| cat_orange | `#F29E4C` | cat fur |
| cat_stripe | `#D9772B` | tabby stripes |
| cat_cream | `#FFE1B8` | muzzle, belly, paw tips |
| cat_pink | `#F48FA0` | nose, inner ears, blush |
| robot_shell | `#9ADBEA` | robot body |
| robot_shade | `#5FA9C2` | robot lower shading, side pods |
| robot_screen | `#233645` | face screen |
| robot_glow | `#7CFFC4` | eyes, smile, thruster |
| accent_red | `#FF6B6B` | antenna tip, alerts |
| floor | `#F6E7CB` | default floor |
| floor_line | `#E8D3AE` | floor boards, grid |
| wall_top | `#C99C74` | wall / furniture footprint |
| wall_front | `#A77B5A` | wall / furniture front face |
| water | `#6EC1E4` | puddle hazard |
| water_light | `#A8DDF2` | puddle ripples |
| danger | `#E8574A` | hazard highlight |
| goal | `#B98AE0` | cat bed rim, sofa top |
| goal_light | `#D7B8F0` | cat bed cushion |
| sofa_front | `#946BB8` | sofa front face |
| yarn_dark | `#C94848` | yarn strands (ball uses accent_red) |
| sunbeam | `#FFF2A8` | distraction light |
| highlight | `#FFFFFF` | eye glints, specular highlights (with opacity) |

## Git
Conventional commits, no AI signatures or attribution. Commit only after `tools/validate.sh` passes.
