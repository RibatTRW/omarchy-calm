.pragma library

// Pure data-in / data-out helpers for omarchy-calm. No Qt imports, so every
// function here can be exercised by a plain JS test harness.

// ---------------------------------------------------------------------------
// Breathing
//
// In 4 s, out 6 s is a 10 s breath. That number is not decorative: 60 s is a
// whole multiple of 10 s, so *any* whole-minute session length is a whole
// number of breaths and the session can end exactly on a completed exhale
// instead of cutting a breath in half.
// ---------------------------------------------------------------------------
var INHALE_SECS = 4
var EXHALE_SECS = 6
var CYCLE_SECS = INHALE_SECS + EXHALE_SECS
var DEFAULT_MINUTES = 3

// Bundled soundscapes. Every one is CC0 - see CREDITS.md.
var SOUNDS = ["rain", "waves", "forest", "wind", "fire"]
var SOUND_LABELS = {
  rain: "Rain",
  waves: "Waves",
  forest: "Forest",
  wind: "Wind",
  fire: "Fire"
}

function soundLabel(name) {
  var key = String(name || "")
  if (SOUND_LABELS[key]) return SOUND_LABELS[key]
  return key
}

function clamp(value, lo, hi) {
  var n = Number(value)
  if (!isFinite(n)) return lo
  return Math.max(lo, Math.min(hi, n))
}

// ---------------------------------------------------------------------------
// Configuration
//
// There is exactly one config file: the widget's inline entry in
// ~/.config/omarchy/shell.json (written by `omarchy bar set ribattrw.calm ...`).
// The overlay re-reads it so the reminder schedule follows the same settings
// the bar shows, and the idle thresholds come from Omarchy's own `idle` block
// so the pause window tracks the compositor instead of a hardcoded guess.
// ---------------------------------------------------------------------------
var CONFIG_SCHEMA = {
  minutes: "int",
  sound: "str",
  volume: "int",
  reminders: "bool",
  reminderMinutes: "int",
  dayStart: "str",
  dayEnd: "str"
}

function defaultConfig() {
  return {
    minutes: DEFAULT_MINUTES,
    sound: "rain",
    volume: 40,
    reminders: true,
    reminderMinutes: 50,
    dayStart: "09:00",
    dayEnd: "20:00",
    // Omarchy's idle thresholds, not ours: used only to size the window in
    // which a pause is allowed to start a session.
    idleScreensaver: 150,
    idleLock: 300
  }
}

function applyConfig(cfg, entry) {
  if (!entry || typeof entry !== "object") return cfg
  for (var key in CONFIG_SCHEMA) {
    if (entry[key] === undefined || entry[key] === null) continue
    var type = CONFIG_SCHEMA[key]
    if (type === "bool") cfg[key] = entry[key] === true || entry[key] === "true"
    else if (type === "int") {
      var n = Number(entry[key])
      if (isFinite(n)) cfg[key] = n
    } else cfg[key] = String(entry[key])
  }
  return cfg
}

function normaliseConfig(cfg) {
  cfg.minutes = Math.round(clamp(cfg.minutes, 1, 60))
  cfg.volume = Math.round(clamp(cfg.volume, 0, 100))
  cfg.reminderMinutes = Math.round(clamp(cfg.reminderMinutes, 10, 240))
  if (minutesOfDay(cfg.dayStart) < 0) cfg.dayStart = "09:00"
  if (minutesOfDay(cfg.dayEnd) < 0) cfg.dayEnd = "20:00"
  if (String(cfg.sound) === "") cfg.sound = "rain"
  return cfg
}

function configFromShell(raw, pluginId) {
  var cfg = defaultConfig()
  var parsed
  try {
    parsed = JSON.parse(raw || "{}")
  } catch (e) {
    return normaliseConfig(cfg)
  }
  if (!parsed || typeof parsed !== "object") return normaliseConfig(cfg)

  var entries = []
  if (parsed.bar && parsed.bar.layout && typeof parsed.bar.layout === "object") {
    for (var section in parsed.bar.layout) {
      if (Array.isArray(parsed.bar.layout[section])) entries = entries.concat(parsed.bar.layout[section])
    }
  }
  if (Array.isArray(parsed.plugins)) entries = entries.concat(parsed.plugins)

  var wanted = String(pluginId || "")
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (entry && String(entry.id) === wanted) {
      applyConfig(cfg, entry)
      break
    }
  }

  if (parsed.idle && typeof parsed.idle === "object") {
    var screensaver = Number(parsed.idle.screensaver)
    var lock = Number(parsed.idle.lock)
    if (isFinite(screensaver) && screensaver > 0) cfg.idleScreensaver = screensaver
    if (isFinite(lock) && lock > 0) cfg.idleLock = lock
  }
  return normaliseConfig(cfg)
}

// ---------------------------------------------------------------------------
// Sessions. Deadlines are absolute wall-clock milliseconds, never a countdown
// that gets decremented on a tick: after a suspend, `Date.now()` has moved on
// and the comparison still lands on the right answer.
// ---------------------------------------------------------------------------
function sessionEndMs(startMs, minutes) {
  return startMs + Math.round(clamp(minutes, 1, 60)) * 60000
}

function progressOf(startMs, endMs, nowMs) {
  var span = endMs - startMs
  if (span <= 0) return 1
  return Math.max(0, Math.min(1, (nowMs - startMs) / span))
}

// Where the breath is `t` seconds into the cycle. Half-cosine easing so the
// movement starts and stops softly - linear motion reads as mechanical, and
// breath is not mechanical.
function breathAt(t) {
  var into = ((t % CYCLE_SECS) + CYCLE_SECS) % CYCLE_SECS
  if (into < INHALE_SECS) {
    var x = INHALE_SECS > 0 ? into / INHALE_SECS : 1
    return {
      label: "Breathe in",
      secsLeft: Math.max(1, Math.ceil(INHALE_SECS - into)),
      fullness: 0.5 - 0.5 * Math.cos(Math.PI * x)
    }
  }
  var y = (into - INHALE_SECS) / EXHALE_SECS
  return {
    label: "Breathe out",
    secsLeft: Math.max(1, Math.ceil(CYCLE_SECS - into)),
    fullness: 0.5 + 0.5 * Math.cos(Math.PI * y)
  }
}

// ---------------------------------------------------------------------------
// Quiet hours and deadlines
// ---------------------------------------------------------------------------
function minutesOfDay(hhmm) {
  var parts = String(hhmm || "").split(":")
  if (parts.length < 2) return -1
  var h = Number(parts[0])
  var m = Number(parts[1])
  if (!isFinite(h) || !isFinite(m)) return -1
  if (h < 0 || h > 23 || m < 0 || m > 59) return -1
  return h * 60 + m
}

function atMinuteOfDay(ms, minuteOfDay) {
  var d = new Date(ms)
  d.setSeconds(0, 0)
  d.setHours(Math.floor(minuteOfDay / 60), minuteOfDay % 60, 0, 0)
  return d.getTime()
}

// The first moment at or after `ms` that falls inside the allowed window.
// Outside the window this jumps straight to the next window's start rather
// than walking the interval forward, so the first nudge of the day lands on
// the configured start time instead of whenever the interval happened to drift.
function firstAllowedAtOrAfter(ms, startStr, endStr) {
  var start = minutesOfDay(startStr)
  var end = minutesOfDay(endStr)
  if (start < 0 || end < 0 || start >= end) return ms

  var todayStart = atMinuteOfDay(ms, start)
  if (ms < todayStart) return todayStart

  var todayEnd = atMinuteOfDay(ms, end)
  if (ms >= todayEnd) {
    var next = new Date(todayStart)
    next.setDate(next.getDate() + 1)
    return next.getTime()
  }
  return ms
}

function inAllowedHours(ms, startStr, endStr) {
  var start = minutesOfDay(startStr)
  var end = minutesOfDay(endStr)
  if (start < 0 || end < 0 || start >= end) return true
  var d = new Date(ms)
  var current = d.getHours() * 60 + d.getMinutes()
  return current >= start && current < end
}

function nextDeadline(afterMs, intervalMs, startStr, endStr) {
  return firstAllowedAtOrAfter(afterMs + Math.max(60000, intervalMs), startStr, endStr)
}

// How long a heads-up may wait for the user to actually pause. Sized off
// Omarchy's own idle threshold: a pause only counts once omarchy.idle would
// call it idle, so the window has to outlive that threshold with slack.
function reminderGraceMs(cfg) {
  var firstIdle = Math.min(
    isFinite(cfg.idleScreensaver) && cfg.idleScreensaver > 0 ? cfg.idleScreensaver : 150,
    isFinite(cfg.idleLock) && cfg.idleLock > 0 ? cfg.idleLock : 300
  )
  return clamp(firstIdle + 60, 180, 900) * 1000
}

// ---------------------------------------------------------------------------
// Persistent state. One file, written only by the overlay:
//   days     - boolean per date, "was this day kept". Never counts, never
//              totals; the bar only ever asks whether *today* is kept.
//   session  - absolute start/end ms while a session runs, else null.
//   ambient  - whether the standalone soundscape loop is meant to be playing.
// ---------------------------------------------------------------------------
function emptyState() {
  return { days: {}, session: null, ambient: false, sound: "" }
}

function parseState(raw) {
  var parsed
  try {
    parsed = JSON.parse(raw || "{}")
  } catch (e) {
    return emptyState()
  }
  if (!parsed || typeof parsed !== "object") return emptyState()
  return {
    days: (parsed.days && typeof parsed.days === "object") ? parsed.days : {},
    session: (parsed.session && typeof parsed.session === "object") ? parsed.session : null,
    ambient: parsed.ambient === true,
    sound: typeof parsed.sound === "string" ? parsed.sound : ""
  }
}

function dayKey(date) {
  var d = date || new Date()
  var month = d.getMonth() + 1
  var day = d.getDate()
  return d.getFullYear() + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day
}

function isKept(state, key) {
  return !!(state && state.days && state.days[key])
}

// Trim instead of accumulating: this map exists to answer one question
// ("is today kept?"), so it must never grow into a history view.
function keepDay(state, key) {
  var days = {}
  for (var k in state.days) days[k] = state.days[k]
  days[key] = true
  var keys = Object.keys(days).sort()
  while (keys.length > 60) delete days[keys.shift()]
  return {
    days: days,
    session: state.session,
    ambient: state.ambient,
    sound: state.sound
  }
}

function withSession(state, session) {
  return {
    days: state.days,
    session: session,
    ambient: state.ambient,
    sound: state.sound
  }
}

function withAmbient(state, ambient, sound) {
  return {
    days: state.days,
    session: state.session,
    ambient: !!ambient,
    sound: sound === undefined ? state.sound : String(sound)
  }
}

// JSON travels as a positional argument, so it is data the shell receives and
// never syntax the shell parses.
// The state file is written from QML with FileView.setText() (the same
// mechanism the first-party notifications and clipboard services use), so no
// subprocess is spawned for a file write at all. JSON is serialised here so
// the format stays testable; the trailing newline keeps the file friendly to
// editors and `git diff`.
function stateJson(state) {
  return JSON.stringify(state, null, 2) + "\n"
}

// ---------------------------------------------------------------------------
// Audio playback
//
// mpv is the only external dependency and it ships in omarchy-base. Local file
// in, looped forever, no network, no privileges. --no-config and
// --load-scripts=no keep the user's own mpv setup (and mpv's MPRIS script)
// out of a meditation session.
//
// Resolution order implements the user-folder override: a file of the same
// name in the user's folder wins over the bundled copy, and a name that only
// exists in the user's folder is simply their own sound.
// ---------------------------------------------------------------------------
var AUDIO_SCRIPT = [
  'n="$1"; v="$2"; ud="$3"; sd="$4"',
  'command -v mpv >/dev/null 2>&1 || exit 0',
  'try() {',
  '  [ -f "$1" ] || return 1',
  '  exec mpv --no-config --load-scripts=no --no-video --really-quiet \\',
  '    --loop-file=inf --audio-client-name=omarchy-calm --volume="$v" "$1"',
  '}',
  'for c in "$ud/$n" "$ud/$n.ogg" "$ud/$n.oga" "$ud/$n.opus" \\',
  '         "$ud/$n.mp3" "$ud/$n.wav" "$ud/$n.flac" "$ud/$n.m4a" \\',
  '         "$sd/$n" "$sd/$n.ogg"; do',
  '  try "$c" || true',
  'done',
  'exit 0'
].join("\n")

function audioCommand(sound, volume, userAudioDir, shippedAudioDir) {
  return [
    "sh", "-c", AUDIO_SCRIPT, "calm-audio",
    String(sound), String(clamp(volume, 0, 100)),
    String(userAudioDir), String(shippedAudioDir)
  ]
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------
function headsUpCommand(omarchyPath, pluginId, headline, body) {
  return [
    omarchyPath + "/bin/omarchy-notification-send",
    "-u", "low", headline, body,
    "--exec", omarchyPath + "/bin/omarchy-shell", "shell", "summon", pluginId, "{}"
  ]
}

function noticeCommand(omarchyPath, headline, body) {
  return [omarchyPath + "/bin/omarchy-notification-send", "-u", "low", headline, body]
}
