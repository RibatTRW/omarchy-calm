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
| `assets/audio/cicada.ogg` | Cicadas | Clarisse | CC0 1.0 | https://bigsoundbank.com/cicadas-s3002.html |
| `assets/audio/breath-in.ogg` | Synthesized inhale breath cue (seeded pink noise) | omarchy-calm project | CC0 1.0 | generated — exact command below |
| `assets/audio/breath-out.ogg` | Synthesized exhale breath cue (seeded pink noise) | omarchy-calm project | CC0 1.0 | generated — exact command below |

CC0 1.0 Universal: https://creativecommons.org/publicdomain/zero/1.0/

## What was changed

Each looping source recording was cut to a fixed window and given a **seamless
loop point**: the tail of the window is equal-power crossfaded into its head,
so the last sample and the first sample are consecutive samples of the
original recording and the loop has no click, gap, or level step.

**Every shipped file — five soundscapes, the cicada loop, and both breath
  cues — is then loudness-normalised to −36 LUFS integrated with true peak
  ≤ −1 dBTP** (two-pass EBU R128 measurement applied as one static gain, so
  no time-varying processing ever touches a loop point). −36 LUFS is the mean of
the five original beds; the target and the level table behind the volume
defaults come from the commissioned audio-science research (2026-09-22).
Re-check any re-encode with `tools/verify-loops.py` — it skips the one-shot
`breath-*` cues, which are never looped. Output is Ogg Vorbis at 48 kHz;
total shipped audio is 3.9 MB. Durations: 60 s (rain, waves, forest), 32 s
(wind), 31 s (fire), 40.000 s (cicada — exactly four breath cycles), and
4.000 s / 6.000 s (cues — one breath phase each).

The matching matters: the source recordings arrive at wildly different
levels (−24 to −42 LUFS), and without it the same knob would mean a
different loudness for every file. The loudness pass is what makes
`volume`, `cicadaVolume`, and `breathVolume` mean what they say.

The looping itself is done at playback by `mpv --loop-file=inf`, which was
measured to be gapless on this stack.

## Regenerated and synthesized files (2026-09-22)

### `assets/audio/cicada.ogg` — Cicadas by Clarisse, CC0 1.0

Derived from `cicada-bigsoundbank-3002-source.wav` ("Cicadas", Clarisse,
https://bigsoundbank.com/cicadas-s3002.html, CC0 verified on the source page
2026-09-22). Processing — no third-party material added, no AI generation:

1. re-cut to exactly 40.000 s from the 48.471042 s source (window
   `[4.235521 s, 44.235521 s]`, equal-power √-curve crossfade of
   4.235521 s — the same recipe as the five soundscapes; 40.000 s = four
   10 s breath cycles, so loop restarts stay on the pacer's grid);
2. baked high-shelf tilt `treble=f=3000:g=-6:w=0.5` (tames the 4–8 kHz
   ridge that would otherwise sit on top of the breath-cue band);
3. loudness-normalised to −36 LUFS / TP ≤ −1 dBTP (static gain).

Ogg Vorbis q4, 40.000 s, loop point verified with `tools/verify-loops.py`.

### `assets/audio/breath-in.ogg` and `breath-out.ogg` — self-authored, CC0 1.0

Synthesized deterministically with ffmpeg from seeded pink noise
(`anoisesrc`): no third-party recordings, no samples, no AI generation —
authored by this project and dedicated to the public domain under CC0 1.0
(the exact commands are the licence record). Regenerated 2026-09-22 per the
audio-science report §6.2: the inhale attack shortened to 0.4 s so the cue
reaches −6 dB of plateau within 0.4 s (phase onset legible ≤ 0.5 s), the
exhale band-pass centre moved 620 → 820 Hz (away from where the wind/waves
maskers peak), then both normalised to −36 LUFS / TP ≤ −1 dBTP.

```bash
# breath-in.ogg — 4.000 s, seed 42, centre 1050 Hz Q1.1, 0.4 s ipar attack
ffmpeg -y -f lavfi -i "anoisesrc=color=pink:duration=4:seed=42:amplitude=0.6" \
  -af "aformat=sample_rates=48000:channel_layouts=stereo,highpass=f=220,lowpass=f=3400,bandpass=f=1050:width_type=q:width=1.1,afade=t=in:st=0:d=0.4:curve=ipar,afade=t=out:st=3.5:d=0.5,volume=0.9,alimiter=limit=0.9" \
  -c:a libvorbis -q:a 5 breath-in.ogg
# then static gain to -36 LUFS (two-pass EBU R128 measurement)

# breath-out.ogg — 6.000 s, seed 17, centre 820 Hz Q1.0
ffmpeg -y -f lavfi -i "anoisesrc=color=pink:duration=6:seed=17:amplitude=0.6" \
  -af "aformat=sample_rates=48000:channel_layouts=stereo,highpass=f=260,lowpass=f=2600,bandpass=f=820:width_type=q:width=1.0,afade=t=in:st=0:d=0.6,afade=t=out:st=1.0:d=5:curve=ipar,volume=0.85,alimiter=limit=0.9" \
  -c:a libvorbis -q:a 5 breath-out.ogg
# then static gain to -36 LUFS (two-pass EBU R128 measurement)
```

The five soundscapes were moved from their previous −16 LUFS remaster to the
same −36 LUFS target with plain static gain (measure → `volume=<g>dB`),
which leaves their loop points intact apart from the single re-encode.

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
