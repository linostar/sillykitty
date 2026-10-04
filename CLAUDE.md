# Silly Kitty

Jam entry for **Jamference: AI Game Jam Hack 1** (theme "Cat and Robot"). Deadline **2026-10-09 07:00 UTC+3**.
Concept "Laser Lure": the player steers a hovering robot; an AI-driven cat stalks the robot, gets distracted,
flees threats and naps; lure it to its bed. Plan and acceptance criteria: `.claude/plans/main.md`.

## Hard rule: Movement Input Only (mandatory jam restriction)
- The only input actions are `move_left`, `move_right`, `move_up`, `move_down` (arrows, WASD, gamepad d-pad, left stick).
- Read input only via `Input.get_vector(...)` / `Input.is_action_*` with literal `move_*` names. Never raw keys, mouse, touch or joypad APIs.
- No buttons or clickable UI. Every `Control` uses `mouse_filter = IGNORE` and `focus_mode = NONE`. Menus are rooms you drive through; restarts are automatic.
- `tools/check_project.gd` fails validation on: input actions other than `move_*` or overridden `ui_*` actions; raw key/mouse/touch/gesture/joypad or pointer APIs, `_input`/`_unhandled_input` callbacks, any-key checks (`is_anything_pressed`, `is_pressed()`), physics picking and non-`move_*` action reads in any `.gd`, `.tscn` or `.tres` (embedded scripts included); clickable Controls created in code; Controls in scenes that are not `IGNORE`/`NONE`. It is a text and scene scan, not a proof, so still review input code by hand.

## Layout
```
CLAUDE.md
.claude/plans/main.md      plan + acceptance criteria
sillykitty/                Godot 4.7.1 project (Compatibility renderer, 1280x720, canvas_items stretch, keep aspect)
  art/                     hand-authored SVG sprite parts
  audio/sfx/               generated WAV sound effects (tools/sfx.py), committed
  audio/music/             generated MP3 music loops + their loop settings in .import (tools/music.py), committed
  fonts/                   Fredoka (Google Font, SIL OFL 1.1) + OFL.txt; fredoka_semibold.tres is the project's default font
  data/cat_tuning.tres     every cat behaviour number (CatTuning resource)
  scenes/                  title_room (main scene), end_room, game (the Game autoload), hud, robot, cat, hazards (puddle, vacuum, dog), props, confetti; scenes/levels/level_NN.tscn
  scripts/                 one script per scene type (class_name = file name in PascalCase)
tools/                     outside the Godot project, never imported or exported
  check_project.gd         restriction + strict-compile gate (run by validate.sh)
  test_gameplay.gd         headless gameplay tests (run by validate.sh)
  sfx.py                   deterministic stdlib synthesiser for every sound effect
  music.py                 stdlib chiptune synthesiser + lame MP3 encode for both music loops
  run_main.gd              headless run of the main scene for validate.sh (quits without audio leaks)
  validate.sh              import + project check + gameplay tests + headless run
  build_web.sh             validate + web export + smoke test + itch zip
  smoke_web.mjs            Playwright (system Chrome) smoke test of the web export
  resume_web.mjs           Playwright check: clear level 1 by keyboard, reload, game resumes at level 2
  web_util.mjs             shared static server + headless Chrome launcher for the Playwright checks
  package.json, package-lock.json   pinned Playwright dev dependency
build/                     git-ignored: web export, logs, smoke screenshot, sillykitty.zip
```

## Commands (run from repo root)
`GODOT` overrides the Godot binary (default `/Applications/Godot.app/Contents/MacOS/Godot`).
- One-time tool setup: `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix tools ci` (uses installed Google Chrome).
- Validate (run after every change): `tools/validate.sh` (each Godot call is killed after `GODOT_TIMEOUT` seconds, default 300)
- Smoke test an existing export only: `npm --prefix tools run smoke` (or `node tools/smoke_web.mjs [buildDir]`, default `build/web`); screenshot goes to `build/smoke.png`. Env: `SMOKE_BOOT_TIMEOUT_MS`, `SMOKE_SETTLE_MS`.
- Resume-after-reload check of an existing export: `npm --prefix tools run resume` (or `node tools/resume_web.mjs [buildDir]`). Env: `RESUME_BOOT_TIMEOUT_MS`, `RESUME_CLEAR_TIMEOUT_MS`. It replays real-time arrow keys anchored on level 1's walls, so redesigning level 1 means re-checking `LEVEL_1_KEYS`.
- Release build for itch.io: `tools/build_web.sh` → `build/sillykitty.zip` (upload as HTML, "played in the browser", viewport 1280x720, SharedArrayBuffer off).
- Regenerate sound effects: `python3 tools/sfx.py` (writes `sillykitty/audio/sfx/*.wav`, byte-identical on every run).
  `hum.wav` (vacuum) loops through `edit/loop_mode=2` in `hum.wav.import`; keep that line if the import file is ever recreated.
- Regenerate music: `python3 tools/music.py` (needs `lame` and `ffmpeg`; the committed files were made with LAME 4.0 and ffmpeg 9.0.2; writes `sillykitty/audio/music/{title,play}.mp3`, byte-identical with the same lame version since its LAME tag records the encoder, and switches their loop on in the `.mp3.import` files). Edit a track by editing its note patterns in `music.py`.
- Run only the gameplay tests: `"$GODOT" --headless --path sillykitty --fixed-fps 60 --script "$PWD/tools/test_gameplay.gd"`.
- Logs for any failure: `build/logs/{import,check,test,run,export}.log`.

Gotchas:
- Godot exits 0 even when a `--script` fails to compile. Never trust its exit code for script runs; `validate.sh` requires the explicit `check_project: OK` / `test_gameplay: OK` lines and fails on any ERROR/WARNING in their logs.
- Quitting a script run right after freeing a playing sound reports leaked `AudioStreamPlayback` objects; `test_gameplay.gd` and `run_main.gd` stop the autoload's music (and drop its stream) and wait in real time before quitting. That is why validate.sh runs the main scene through `run_main.gd` instead of `--quit-after`.
- MP3 loops are seamless only while lame writes its LAME/Xing tag: Godot (like ffmpeg) uses it to trim the encoder delay and padding, so the decoded file is exactly one loop. Never encode with `lame -t` (it drops the tag); `music.py` decodes each file and fails if it is not exactly one loop long.
- A fresh clone has no import cache, and its first import errors because the project's default font loads before its TTF is imported; `validate.sh` runs a priming import first and tolerates only those font errors there.
- Windowed screenshot scripts run unpaced (hundreds of fps), so particles barely move between frames; wait in real time before capturing.

## Gameplay architecture
- Physics layers: 1 = walls, 2 = robot, 3 (bit value 4) = cat. Robot, cat and dog collide only with walls (the dog has no layer of its own). Hazards are `Area2D` with `collision_layer = 0`, `collision_mask = 4`, so only the cat triggers them (the robot hovers).
- Cat brain (`scripts/cat.gd`): each physics tick scores idle, chase robot, each available distraction (group `distractions`), each bed in range (group `goals`) and fleeing (while a scary threat was seen within the last `flee_linger` s); the current choice gets `hysteresis`. The robot, distractions, beds and threats count only in line of sight (raycast against layer 1; a robot out of sight leaves the cat idle, so its nap meter fills), and a distraction or bed the cat cannot get closer to for `give_up_time` is ignored for `give_up_cooldown`. A threat in range also ends play with a distraction. A fleeing cat runs along walls instead of into them, and one that stays below `flee_stall_speed` for `flee_give_up_time` (cornered) ignores the threats it sees for `flee_ignore_time`. Level design: keep vacuum loops a little away from walls they drive at. The player has no restart button, so no cat or dog state may be able to last forever. Terminal states `NAP` / `FAILED` / `CLEARED` (`is_over()`) emit `failed(reason, sound)` / `reached_goal`.
- Nap meter (`Cat.nap`, 0..1): fills over `nap_fill_time` while the cat is `IDLE` and the robot has moved at least once (`Robot.has_moved`), drains over `nap_drain_time` otherwise; full = `NAP` fail with the yawn.
- `ThoughtBubble` (child of the cat) shows one icon per non-terminal state plus `NAP`, and the nap meter above it; it hides on `FAILED` / `CLEARED`.
- Each `Hazard` exports its fail `reason` text, `sound`, `splashes` (wet or dizzy fail animation) and `fear_radius`; a hazard with `fear_radius > 0` joins group `threats` and is fled while its `scary` flag is on. The level plays the hazard's sound.
- `Vacuum` (extends `Hazard`) drives its `waypoints` loop (parent coordinates) at `speed` forever, humming. `Dog` (`CharacterBody2D`, export `cat`) sleeps until it sees the cat (line of sight) within `wake_radius`, which is far wider than its bite so the cat always wakes it before touching it, then barks and chases for `chase_time`, then returns home and sleeps, or lies down where it is after `return_time`; it stops waking and chasing once `cat.is_over()`; its child `Bite` hazard is scary only while awake. Set a level's `Dog.cat` like `Cat.robot`. Level design: keep a sleeping dog at least 60 px from furniture corners, or the cat can round the corner into its bite without ever being seen (touching a sleeping dog fails too).
- `Game` autoload (`scenes/game.tscn` + `scripts/game.gd`, class `GameState`) owns `LEVEL_PATHS` (add every new level there), linear progression (title room -> furthest unlocked level; clear -> next level, fail -> retry after 1.6 s with `retrying` set, clear of the last level -> end room for 7 s -> level 1, and the furthest level resets to 1 so a reload resumes there too; stars are kept) and the save `user://progress.json` (furthest level, best stars). It also owns the music (`title_music` in the title and end rooms, `level_music` in levels; it keeps playing across retries) and a curtain that fades every scene change in. It logs every load, save and transition with a `[Game]` prefix; a corrupt save is reported once and replaced.
- `TitleRoom` (main scene) shows the title, the restriction sentence (`RESTRICTION_TEXT`) and progress; the live robot's first movement starts the game after 0.6 s. `EndRoom` shows `GameState.END_TEXT`, the star total, credits and confetti. Both call `Game.enter_room()`.
- Reach the autoload with `get_node(GameState.AUTOLOAD_PATH) as GameState`, never the global name `Game`: test scripts compile before autoloads exist, so any script naming `Game` breaks every test.
- `Level` (`scripts/level.gd`) exports `time_limit` and `hint`, runs the countdown (starts on the robot's `started_moving`, red and ticking for the last 10 s or the last 40% of a shorter limit, time-up = fail), awards 1-3 stars from the time left (3 at >= 20% of the limit, 2 at >= 10%) and only reports `finished(cleared, stars)`; `Game` decides what loads next. No input is ever needed to continue.
- Every level instances `scenes/hud.tscn` (unique name `%Hud`) and marks its robot and cat with unique names `%Robot` and `%Cat`.
- Juice: the HUD shows a "Level N" intro card (not on retries), the outcome banner on a panel, stars popping in with a rising chime, and a confetti burst on a clear; the countdown pulses on each tick; the level root shakes on a fail (the HUD is a CanvasLayer, so it stays still); the cat kicks up dust while running.
- Levels: `RoomFloor` draws the floor; border `Wall`s go under `Room`; furniture `Wall`s, the robot and the cat go under the y-sorted `Actors` node. `Wall` origin is the bottom-centre of its footprint. `Wall` and `RoomFloor` are `@tool` scripts, so levels can be laid out visually in the editor.
- Positions of the robot, cat and props are their feet; visuals are drawn upward from there.
- Robot, cat and dog use `wall_min_slide_angle = 0` so they slide along furniture even when pushing into it almost head-on (the default 15 degrees freezes a chasing cat against walls).
- Levels 1-8 (`LEVEL_PATHS`) introduce one mechanic each: puddle (1), yarn (2), puddle maze (3), vacuum (4), long route with nap pressure (5), dog (6), vacuum + puddles + yarn (7), finale with dog, vacuum and puddles (8). `tools/test_gameplay.gd` holds one scripted solution route per level (`LEVEL_ROUTES`, flown through the `move_*` actions in 8 directions like a keyboard, turning back for the cat like a player would) and checks each level's mechanics, that its route clears it with 3 stars, that flying straight at the bed fails, that racing ahead on level 5 ends in a nap, and the time-limit rules, measured on the faster of the route as written and the same route flown without ever turning back: limit / clear time >= 1.25 everywhere, >= 1.8 on levels 1-2, <= 1.5 on levels 7-8, never rising from one level to the next. The test prints the measured ratios; after changing a level or any cat, vacuum or dog number, re-run the tests and re-set `time_limit` from them.

## GDScript conventions
- Godot 4 style guide: tabs, `snake_case` files/functions/variables, `PascalCase` nodes and `class_name`, `UPPER_SNAKE` constants, signals in past tense.
- Static typing everywhere. `project.godot` raises every default GDScript warning to **error**, so warnings fail validation (release exports skip warnings, players are unaffected). Prefix intentionally unused parameters with `_`.
- No silent failures: check results of loads, file and save operations; report failures with `push_error` including the path or node involved.

## Art pipeline
- Sprites are hand-authored SVG in `sillykitty/art/`, imported natively by Godot. Characters are built from separate parts animated procedurally in-engine; no sprite sheets.
- Style: flat fills, `#3B2C35` ink outline 3px (2.5px on small parts) with round joins, soft highlights, shadows from `shadow.svg`.
- Cat parts (side view facing right, flip for left): `cat_body`, `cat_head`, `cat_ear` (x2), `cat_tail` (pivot at the tail base, bottom-right), `cat_paw` (x4).
- Robot parts (front view): `robot_body`, `robot_face`, `robot_antenna` (pivot at the stem base), `robot_thruster`, plus `shadow`.
- Vacuum parts (3/4 view): `vacuum_body`, `vacuum_brush` (x2, spun under a 0.45 y-squash for perspective), `vacuum_light`.
- Dog parts (side view facing right): `dog_body`, `dog_head`, `dog_eyelid` (shown while asleep), `dog_ear` (pivot at the top), `dog_tail` (pivot at the base, bottom-right), `dog_paw` (x4).
- Thought bubble: `bubble`, icons `icon_idle`, `icon_heart` (chase), `icon_alert` (flee), `icon_zzz` (nap, also the dog's snore); distracted and go-to-bed reuse `yarn` and `cat_bed`.
- Props: `puddle` (hazard), `cat_bed` (goal), `yarn` (distraction); HUD: `star`. Confetti is `scenes/confetti.tscn` (CPUParticles2D squares in palette colours). Walls and floors are drawn in code (`wall.gd`, `room_floor.gd`).

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
| goal | `#B98AE0` | cat bed rim (reserved for the goal) |
| goal_light | `#D7B8F0` | cat bed cushion |
| sofa_top | `#8FBF8A` | sofa footprint |
| sofa_front | `#6E9E69` | sofa front face |
| yarn_dark | `#C94848` | yarn strands (ball uses accent_red) |
| sunbeam | `#FFF2A8` | distraction light |
| star | `#FFC94D` | star rating, vacuum brush bristles |
| vacuum_shell | `#D5DCE3` | vacuum lid |
| vacuum_shade | `#B4BEC8` | vacuum lid shading |
| vacuum_trim | `#56606B` | vacuum side, button, brush hub |
| dog_fur | `#C4A27F` | dog fur |
| dog_patch | `#8A6446` | dog ear, back patch, brow |
| dog_belly | `#F1E2CC` | dog muzzle, belly, paw tips |
| nap | `#8A8FE0` | nap meter, Zzz icon |
| highlight | `#FFFFFF` | eye glints, specular highlights (with opacity) |

## Git
Conventional commits, no AI signatures or attribution. Commit only after `tools/validate.sh` passes.
