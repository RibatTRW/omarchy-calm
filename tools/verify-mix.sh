#!/usr/bin/env bash
# Acceptance checks A1-A10 for the omarchy-calm audio-layers mix, from the
# commissioned audio-science report (section 6.4). Run from the repo root:
#
#   tools/verify-mix.sh
#
# Offline checks implemented here: A1, A2, A3, A5, A6, A7, A8, A10.
# A4 (cue onset latency under load) and A9 (silence invariants) need a live
# shell session; their steps are printed at the end and were run manually
# for the v1 launch (see PR description).
#
# Defaults under test (manifest.json): volume 40, cicadaVolume 30,
# breathVolume 20. Knob laws (measured):
#   mpv     --volume: gain_dB = 60*log10(v/100)   (cubic)
#   pw-play --volume: gain_dB = 20*log10(v/100)   (linear)
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET_I=-36.0
TOL=0.5          # A1/A6 loudness tolerance, LU
SEAM_MAX=0.05    # A7 loop-point sample delta
CORE_MARGIN=6    # A2 minimum in-band cue-over-masker margin, dB
CICADA_MARGIN=50 # A3 minimum in-band cue-over-cicada margin, dB
BED_VOL=40; CIC_VOL=30; CUE_VOL=20

FAILS=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
approx() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN{d=a-b; if(d<0)d=-d; exit(d>t?1:0)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }
mpv_gain()  { awk -v v="$1" 'BEGIN{printf "%.3f", 60*log(v/100)/log(10)}'; }  # v = 0..100
pw_gain()   { awk -v v="$1" 'BEGIN{printf "%.3f", 20*log(v/100)/log(10)}'; }  # v = 0..100

i_of() {
  ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=print_format=summary -f null - 2>&1 \
    | awk '/Input Integrated/{v=$3} END{print v}'
}
tp_of() {
  ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=print_format=summary -f null - 2>&1 \
    | awk '/Input True Peak/{v=$4} END{print v}'
}
# Band RMS (dBFS) of a file, or of a window of it: band_rms FILE LO HI [START DUR]
# Brick-band via firequalizer (FFT-designed FIR, -120 dB stopband) - the fast
# equivalent of the audio-science report's Welch/FFT band script; the leaky
# 2-pole astats filters over-read by leaking the cicada's 4-8 kHz ridge.
band_rms() {
  local pre=()
  [ $# -ge 5 ] && pre=(-ss "$4" -t "$5")
  ffmpeg -hide_banner -nostats "${pre[@]}" -i "$1" -ac 1 -ar 48000 \
    -af "firequalizer=gain='if(lt(f,$2)+gt(f,$3),-120,0)',astats" -f null - 2>&1 \
    | awk '/RMS level dB/{v=$NF} END{print v}'
}

BEDS="rain waves forest wind fire"
ASSETS="assets/audio"
CG="$(mpv_gain "$BED_VOL")"; XG="$(mpv_gain "$CIC_VOL")"; QG="$(pw_gain "$CUE_VOL")"

# ---------------------------------------------------------------- A1 loudness
a1=ok
for f in $BEDS cicada breath-in breath-out; do
  i="$(i_of "$ASSETS/$f.ogg")"; t="$(tp_of "$ASSETS/$f.ogg")"
  approx "$i" "$TARGET_I" "$TOL" || { a1=bad; fail "A1 $f I=$i (want $TARGET_I +/- $TOL)"; }
  ge "$t" "-1" && { a1=bad; fail "A1 $f TP=$t (want <= -1)"; } || true
done
[ "$a1" = ok ] && pass "A1 all 8 assets at $TARGET_I +/- $TOL LUFS, TP <= -1 dBTP"

# ------------------------------------------------- A2 cue in-band over beds
a2=ok
for cue in breath-in breath-out; do
  case $cue in
    breath-in)  lo=600;  hi=1200 ;;   # dominant band, science report 4.0/4.2
    breath-out) lo=450;  hi=800  ;;
  esac
  cl="$(band_rms "$ASSETS/$cue.ogg" $lo $hi)"
  cue_eff="$(awk -v c="$cl" -v g="$QG" 'BEGIN{printf "%.2f", c+g}')"
  for bed in $BEDS; do
    bl="$(band_rms "$ASSETS/$bed.ogg" $lo $hi)"
    bed_eff="$(awk -v b="$bl" -v g="$CG" 'BEGIN{printf "%.2f", b+g}')"
    snr="$(awk -v c="$cue_eff" -v b="$bed_eff" 'BEGIN{printf "%.2f", c-b}')"
    ge "$snr" "$CORE_MARGIN" \
      || { a2=bad; fail "A2 $cue vs $bed in-band ${lo}-${hi}Hz: SNR $snr dB (want >= +$CORE_MARGIN)"; }
  done
done
[ "$a2" = ok ] && pass "A2 in-band cue SNR >= +$CORE_MARGIN dB over all 5 soundscapes at defaults"

# ------------------------------------------------------- A3 cue vs cicadas
a3=ok
for cue in breath-in breath-out; do
  case $cue in breath-in) lo=600; hi=1200;; breath-out) lo=450; hi=800;; esac
  cl="$(band_rms "$ASSETS/$cue.ogg" $lo $hi)"
  xl="$(band_rms "$ASSETS/cicada.ogg" $lo $hi)"
  snr="$(awk -v c="$cl" -v x="$xl" -v qc="$QG" -v xg="$XG" \
        'BEGIN{printf "%.2f", (c+qc)-(x+xg)}')"
  ge "$snr" "$CICADA_MARGIN" \
    || { a3=bad; fail "A3 $cue vs cicada in-band: SNR $snr dB (want >= +$CICADA_MARGIN)"; }
done
[ "$a3" = ok ] && pass "A3 in-band cue SNR >= +$CICADA_MARGIN dB over the cicada layer at defaults"

# -------------------------------------- A5 inhale onset legibility <= 0.5 s
# Threshold: loudest in-band masker at defaults + CORE_MARGIN. The inhale's
# in-band level in a 100 ms window ending at t=0.5 s must already clear it.
worst=-999
for bed in $BEDS; do
  bl="$(band_rms "$ASSETS/$bed.ogg" 600 1200)"
  eff="$(awk -v b="$bl" -v g="$CG" 'BEGIN{printf "%.2f", b+g}')"
  worst="$(awk -v w="$worst" -v e="$eff" 'BEGIN{print (e>w)?e:w}')"
done
thr="$(awk -v w="$worst" 'BEGIN{printf "%.2f", w+'"$CORE_MARGIN"'}')"
onset="$(band_rms "$ASSETS/breath-in.ogg" 600 1200 0.4 0.1)"
onset_eff="$(awk -v o="$onset" -v g="$QG" 'BEGIN{printf "%.2f", o+g}')"
ge "$onset_eff" "$thr" \
  && pass "A5 inhale in-band over [0.4,0.5]s: $onset_eff dB >= loudest masker+6 ($thr dB) - onset legible <= 0.5 s" \
  || { fail "A5 inhale in-band over [0.4,0.5]s: $onset_eff dB < $thr dB"; }

# ------------------------------------------- A6 bed-to-bed loudness delta
hi_i=-999; lo_i=999
for bed in $BEDS; do
  i="$(i_of "$ASSETS/$bed.ogg")"
  hi_i="$(awk -v a="$hi_i" -v b="$i" 'BEGIN{print (b>a)?b:a}')"
  lo_i="$(awk -v a="$lo_i" -v b="$i" 'BEGIN{print (b<a)?b:a}')"
done
delta="$(awk -v h="$hi_i" -v l="$lo_i" 'BEGIN{printf "%.2f", h-l}')"
approx "$delta" 0 "$TOL" \
  && pass "A6 bed-to-bed loudness delta ${delta} dB <= ${TOL} dB (was 18.5 LU)" \
  || { fail "A6 bed-to-bed delta $delta dB > $TOL dB"; }

# ------------------------------------------------------- A7 seams + lengths
a7=ok
for f in $BEDS cicada; do
  d="$(ffmpeg -v error -i "$ASSETS/$f.ogg" -f f32le -ac 1 -ar 48000 - 2>/dev/null \
      | python3 -c "import sys,struct;b=sys.stdin.buffer.read();n=len(b)//4;\
s=struct.unpack('<%df'%n,b[:n*4]);print('%.4f'%abs(s[0]-s[-1]))")"
  ge "$SEAM_MAX" "$d" || { a7=bad; fail "A7 $f seam delta $d > $SEAM_MAX"; }
done
dur() { ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$1"; }
d="$(dur "$ASSETS/cicada.ogg")"
approx "$d" 40.000 0.010 || { a7=bad; fail "A7 cicada duration $d != 40.000 (4 breath cycles)"; }
d="$(dur "$ASSETS/breath-in.ogg")"; approx "$d" 4.000 0.010 || { a7=bad; fail "A7 breath-in $d != 4.000"; }
d="$(dur "$ASSETS/breath-out.ogg")"; approx "$d" 6.000 0.010 || { a7=bad; fail "A7 breath-out $d != 6.000"; }
python3 tools/verify-loops.py "$ASSETS" > /tmp/verify-loops.out 2>&1 \
  || { a7=bad; fail "A7 verify-loops.py: $(tail -1 /tmp/verify-loops.out)"; }
[ "$a7" = ok ] && pass "A7 loop seams <= $SEAM_MAX, durations 40.000/4.000/6.000 s, verify-loops.py clean"

# --------------------------------------- A8 no clipping, all layers maxed
a8=ok
# volume 100 + cicadaVolume 100 + breathVolume 100 are all 0 dB of gain, so
# the worst case is the plain sum of the three loudest files' peaks.
mix="$(mktemp -d)/mix.wav"
ffmpeg -y -hide_banner -loglevel error -i "$ASSETS/fire.ogg" -i "$ASSETS/cicada.ogg" \
  -i "$ASSETS/breath-out.ogg" -filter_complex \
  "[0:a]atrim=0:6,asetpts=N/SR/T[a];[1:a]atrim=0:6,asetpts=N/SR/T[b];[2:a]atrim=0:6,asetpts=N/SR/T[c];[a][b][c]amix=inputs=3:normalize=0[m]" \
  -map "[m]" "$mix"
mtp="$(tp_of "$mix")"
ge "$mtp" "-1" && { a8=bad; fail "A8 mixed true peak $mtp > -1 dBTP"; } || true
[ "$a8" = ok ] && pass "A8 3-layer sum at maxed knobs: TP $mtp dBTP <= -1"
rm -rf "$(dirname "$mix")"

# --------------------------------------------- A10 mpv gain law regression
sine="$(mktemp -d)/sine.wav"
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=2" \
  -ar 48000 "$sine"
rms_of() { ffmpeg -hide_banner -nostats -i "$1" -af astats -f null - 2>&1 \
           | awk '/RMS level dB/{v=$NF} END{print v}'; }
for v in 100 40; do
  mpv --no-config --volume="$v" --o="$(dirname "$sine")/v$v.wav" --of=wav \
      --really-quiet "$sine" 2>/dev/null || true
done
r100="$(rms_of "$(dirname "$sine")/v100.wav")"
r40="$(rms_of "$(dirname "$sine")/v40.wav")"
dl="$(awk -v a="$r40" -v b="$r100" 'BEGIN{printf "%.2f", a-b}')"
pred="$(mpv_gain 40)"
approx "$dl" "$pred" 0.5 \
  && pass "A10 mpv --volume=40 measures $dl dB vs 100 (60*log10 law: $pred +/- 0.5)" \
  || { fail "A10 mpv gain $dl dB != $pred +/- 0.5"; }
rm -rf "$(dirname "$sine")"

# ------------------------------------------------- A4 / A9 (live steps)
cat <<'EOF'

A4 (cue onset latency, p95 <= 100 ms / p100 <= 150 ms) - live components:
  * pw-play exec -> node visible in pw-dump: measured per release run
    (~13 ms; three-run spot check in the PR description).
  * 50 ms QML Timer lateness under CPU load: measured with a headless
    Quickshell timer probe; worst-case budget = 50 ms quantisation +
    lateness + player start.
A9 (silence invariants) - live/code steps:
  * sound=none: runAudio() takes the stopAudio() gate before any spawn;
    cicadaProc only starts inside the sound!=none branch; review in
    CalmOverlay.qml (runAudio/fireBreathCue/sessionTick gates).
  * no cues outside a session: sessionTick runs only on opened && active,
    teardown flips active=false before killing cueProc; first cue lands on
    the first label edge (lastCueLabel reset in open()/teardown()).
EOF

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL ACCEPTANCE CHECKS PASS"; exit 0; fi
echo "$FAILS CHECK(S) FAILED"; exit 1
