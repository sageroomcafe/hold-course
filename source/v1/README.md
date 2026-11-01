# Hold Course — Godot 4 slice (mobile-first web build)

**Engine:** Godot 4.7.2 (free, no subscription). Renderer: **Compatibility** (WebGL 2), so it runs in phone browsers (Android Chrome, iPhone Safari) and desktop browsers.

## Play

- Open the build link on your phone. Tap **TAP TO FLY**. You are already at ~300 km/h.
- **Steer (all directions):** put your thumb down anywhere and **slide** it — up/down/left/right/diagonal. It works like an invisible joystick that appears where you touch: slide further = faster. Let go and the ship coasts to a stop, then drifts gently back toward the middle. On a computer: hold the left mouse button and move, or use arrow keys / WASD.
- Sensitivity is one number: `STEER_SENSITIVITY` at the top of `scripts/ship.gd` (1.0 relaxed, 1.6 default, 2.5 twitchy).
- **Neon portals (2026-11-01):** glowing rings come at you. Fly through the middle = +100 points × combo. Each ring in a row raises the combo (up to x8); missing one only resets the combo. Score is big at the top; best score (and best distance) are saved on the device.
- **Portal sounds (2026-11-01):** every ring plays a soft, soothing tone, and each one is a different note from the last — together they form a slow, dreamy melody (D major pentatonic, so overlapping tails always blend). The tone colour rotates between three soft voices (glass pad, breathy pad, soft marimba). A higher combo adds a low harmony note (x3+) and a faint shimmer an octave up (x6+). A very quiet drone hums underneath while flying. All sounds are generated in code at startup (`scripts/portal_tones.gd`); `build/tools/render_portal_preview.py` renders a listening preview with the same settings.
- **Camera views (2026-11-01):** **CHASE** (behind the ship, as before) or **COCKPIT** (first person from the pilot seat: canopy frame, dashboard with a radar that shows the next ring, a combo meter and soft neon lights, faint centre reticle). Tap the **VIEW** button (eye icon, top-right) any time — the camera flies smoothly into / out of the cockpit in 0.7 s. The tap never steers. You can also pick CHASE / COCKPIT on the start screen, or press **C** / **V** on a computer. The choice is remembered on the device. Cockpit look/layout: `scripts/cockpit.gd`; transition tuning (`VIEW_TRANSITION`, `HEAD_OFFSET`, `COCKPIT_SHAKE`…) at the top of `scripts/main.gd`.
- No asteroids or obstacles; nothing to crash into.
- Portrait is the main layout (one thumb). Landscape works too.

## Where things live

- Project: `lumenforge/projects/hold-course/game/`
  - `scripts/main.gd` builds the whole world in code (speed streaks, stars, neon portals + score/combo, HUD, sound, saving). Portal tuning constants (`PORTAL_SPACING`, `PORTAL_HIT_RADIUS`, `PORTAL_MAX_STEP`, `COMBO_MAX`…) are at the top. Rocks are switched off with `OBSTACLES_ENABLED := false`; set it to `true` to bring back spawning, collision and crash/restart.
  - `scripts/portal_tones.gd` portal tones: scale, melody, voices, echo, drone (all tuning constants at the top).
  - `scripts/cockpit.gd` cockpit interior for the COCKPIT view (built in code, laid out in screen terms so it fits portrait and landscape).
  - `scripts/ship.gd` steering (floating joystick, keyboard, soft edges, recentre) + bank. Growth stub: `ship_profile_id`.
  - `scripts/asteroid.gd` one rock type (unused while `OBSTACLES_ENABLED` is false). Growth stub: `hazard_type`.
- Web build: `lumenforge/projects/hold-course/build/web/` (`index.html`, `index.wasm`, `index.pck`, `index.js` …)
- Screenshots from browser tests: `lumenforge/projects/hold-course/build/screens/`
- Tools: `lumenforge/projects/hold-course/build/tools/`
  - `serve.py` — local static server (wasm MIME type, gzip, no-cache on html)
  - `test_web.py` — headless Chromium test (Pixel 7, iPhone 13, desktop)
  - `make_static_package.sh` — makes `build/deploy/hold-course-web.zip` for static hosts that do not accept the `.pck` file type

## Rebuild / export (on the studio box)

```bash
cd /workspace/lumenforge/projects/hold-course/game
/home/box/bin/godot --headless --path . --import            # first time / after adding files
/home/box/bin/godot --headless --path . --export-release "Web" ../build/web/index.html
```

The Web export preset is in `export_presets.cfg`: thread support OFF (no special server headers needed), VRAM compression for desktop + mobile (ETC2/ASTC), PWA files generated (the service worker is not registered, so a new export shows up on reload).
Export templates live in `~/.local/share/godot/export_templates/4.7.2.stable/` (only the web templates were installed).

## Test in a browser (on the box)

```bash
cd /workspace/lumenforge/projects/hold-course/build
nohup python3 tools/serve.py web 8060 > /tmp/serve.log 2>&1 &
/workspace/dl/venv/bin/python tools/test_web.py http://localhost:8060/index.html all
```

The game publishes a small status object `window.holdCourse` (state, distance, best, x/y, holding, score, bestScore, combo, portalsHit, portalsMissed, nextX/nextY/nextZ of the next ring, sensitivity, soundSeq/lastNote/lastVoice/noteHist/voiceHist of the portal tones, view ('chase'|'cockpit'), viewBlend 0..1, viewTransition, viewInside, and the VIEW button / picker positions; crashes/rocks stay 0 while obstacles are off). The test steers in all four directions, checks release doesn't drift to the edge, and steers through rings using the next-ring position that the test reads, and checks that consecutive portal tones differ. It also checks the start-screen camera picker, toggles chase → cockpit with the VIEW button (no steering drag), steers and flies the portal segment in cockpit view (screenshot `build/screens/<device>-cockpit.png`), toggles back, and checks the view is remembered after a reload.

## Open in the Godot editor (optional)

Godot → **Import** → choose this folder → **F5**.

## Slice goal

First second must feel like POV speed. Steering fair in all directions. Core loop (2026-11-01): fly through neon portals for points + combo. Growth hooks (`hazard_type`, `ship_profile_id`) stay stubs until the slice passes.
