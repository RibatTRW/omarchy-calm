# Credits and audio attribution

Every soundscape shipped in `assets/audio/` is a **CC0 1.0 (Public Domain
Dedication)** recording. Each licence below was read and confirmed on the
source page linked in the last column before the file was included — not
taken from an aggregator's metadata field, and not from an ambiguous
"free download" page.

No track is AI-generated. Nothing here requires attribution under CC0, but
the authors are recorded because they did the work.

| File | Title | Author | Licence | Source page |
|---|---|---|---|---|
| `assets/audio/rain.ogg` | Light Rain on Woodland Floor and Running Stream.wav | thinkingfish | CC0 1.0 | https://freesound.org/people/thinkingfish/sounds/695571 |
| `assets/audio/waves.ogg` | wave loop 2.wav | klangfabrik | CC0 1.0 | https://freesound.org/people/klangfabrik/sounds/428087 |
| `assets/audio/forest.ogg` | sfx_amb_forest_spring_afternoon-01.wav | bajko | CC0 1.0 | https://freesound.org/people/bajko/sounds/385280 |
| `assets/audio/wind.ogg` | Looping Gentle Wind Ambience on an Open Desert Plain.wav | dhallcomposer | CC0 1.0 | https://freesound.org/people/dhallcomposer/sounds/697217 |
| `assets/audio/fire.ogg` | campfire.wav | aerror | CC0 1.0 | https://freesound.org/people/aerror/sounds/350757 |

CC0 1.0 Universal: https://creativecommons.org/publicdomain/zero/1.0/

## What was changed

Each source recording was cut to a fixed window and given a **seamless loop
point**: the tail of the window is equal-power crossfaded into its head, so
the last sample and the first sample are consecutive samples of the original
recording and the loop has no click, gap, or level step. Output is Ogg Vorbis
at 48 kHz. Durations are 60 s (rain, waves, forest), 32 s (wind) and 31 s
(fire); total shipped audio is 2.7 MB.

The looping itself is done at playback by `mpv --loop-file=inf`, which was
measured to be gapless on this stack.

## Files considered but not shipped

These were verified as CC0 too and downloaded during sourcing, but left out
to keep the set to five distinct soundscapes:

- `oceanwaves-5.wav` by Rmutt — CC0 1.0 — https://freesound.org/people/Rmutt/sounds/148283
- `Park ambience - mostly birds` by Mafon2 — CC0 1.0 — https://freesound.org/people/Mafon2/sounds/274175
- `Ambiance_Campfire_Loop_Stereo.wav` by Nox_Sound — CC0 1.0 — https://freesound.org/people/Nox_Sound/sounds/558967
- `Wind ambience` by haniebal — CC0 1.0 — https://freesound.org/people/haniebal/sounds/423314

## Code

The plugin is MIT licensed — see [LICENSE](LICENSE).

Two first-party Omarchy surfaces informed the implementation and are cited
here rather than copied: `shell/plugins/reminders/` (summonable overlay flow)
and `shell/plugins/notifications/Service.qml` (the do-not-disturb flag).
Omarchy itself is MIT licensed.
