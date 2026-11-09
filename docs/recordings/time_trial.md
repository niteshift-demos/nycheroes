# Recording the time trial

A video of the time trial (`scripts/game/time_trial.gd`) in the real game,
recorded with Godot's own Movie Maker: no browser capture, no speed-up.

## What it shows

`tests/time_trial_recording.tscn` loads the main scene (`scenes/world.tscn`)
with the documented default start (Times Square), pedestrians and traffic
as usual, no gangs (`--gangs=0`) and its own settings file (a player name,
so no name prompt, and the stats text switched off, as the options menu
can). It drives the hero only through `HeroInput`, each physics tick, the
way a player's keys would (`tests/trial_pilot.gd`), and presses the real R
key through `Input.parse_input_event`:

1. Runs north into the green start gate (the clock starts), toggles flight
   and flies over checkpoint 1 about 44 m above the street: past the gate's
   25 m reach, so it isn't cleared (the HUD stays at 0 / 4 and its marker
   points back down at the gate). This is the limit on purpose: the gates
   have to be run (or flown low) through.
2. Presses R: the hero is set 25 m before the start gate, the clock reset.
3. Runs the course with super speed on the straights, slowing for the
   corner at West 50th Street (super speed turns slowly), to the finish:
   about 20 s. Holds on the result.

Nothing is teleported mid-action other than Retry itself (the feature's
own path), and no movement, time scale or physics value is changed.

## Commands

```sh
# Linux, no GPU: Xvfb and Mesa's llvmpipe (about 1 frame a second).
GODOT_SILENCE_ROOT_WARNING=1 xvfb-run -n 60 -s "-screen 0 1280x720x24" \
  godot --path . --rendering-driver opengl3 \
  --write-movie /tmp/rec/frames/trial.png --fixed-fps 30 --resolution 1280x720 \
  res://tests/time_trial_recording.tscn \
  -- --solo=1 --gangs=0 --tiles_url=https://nycheroes.party/tiles/
```

With `--fixed-fps 30` the game steps exactly 1/30 s a frame (two physics
ticks at 60 Hz), however long a frame takes to draw, so the footage plays
at true speed. Movie Maker writes numbered PNGs and a WAV. The script
prints `[rec] start frame N` when the city has loaded and the loading
screen has gone, and `[rec] end frame M`; the video keeps frames N..M-1,
every one of them, at 30 fps:

```sh
# Two passes at 4.8 Mbit/s keep the file under 25 MB (CRF 18 made 33 MB).
for pass in 1 2; do
  ffmpeg -y -framerate 30 -start_number N -i /tmp/rec/frames/trial%08d.png \
    -frames:v $((M-N)) -c:v libx264 -pix_fmt yuv420p -b:v 4800k -maxrate 6000k \
    -bufsize 9600k -preset slow -pass $pass -r 30 -movflags +faststart \
    $([ $pass = 1 ] && echo "-an -f mp4 /dev/null" || echo time_trial.mp4)
done
```

The video has no sound: in this sandbox the game ran on Godot's Dummy audio
driver and Movie Maker's WAV came out silent (-91 dB), so it was left out.

The 2026-11-09 take: `[rec] start frame 184`, `[rec] end frame 1322`, 1138
frames, 37.93 s at 30 fps, 1280x720 H.264 (22.3 MB); the run finished in 0:20.03
(splits 5.02, 9.73, 15.32, 20.03 s) after flying over checkpoint 1 at 44 m.
Check with `ffprobe` (1280x720, 30/1 fps, frame count M-N).
