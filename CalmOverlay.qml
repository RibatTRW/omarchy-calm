import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "CalmModel.js" as Model

// omarchy-calm's fullscreen breathing session, the break-reminder scheduler,
// and the single owner of ambient audio playback.
//
// This component is `keepLoaded: true`, so it is instantiated once at shell
// start and stays alive between summons. That is what lets the reminder
// schedule keep running even when no session has ever been opened and lets the
// widget read live session progress off the shared state file.
//
// Trigger a session from anywhere with:
//   omarchy-shell shell summon ribattrw.calm '{}'
//   omarchy-shell shell summon ribattrw.calm '{"minutes":5,"sound":"waves"}'
//
// Design notes that are product decisions, not accidents:
//   * No countdown digits. A ticking clock is the opposite of de-stress;
//     progress is an arc instead. Stats never appear at all - only whether
//     *today* is kept.
//   * The day is marked kept the moment a session starts, so leaving early
//     still counts and there is no way to "fail" a session.
//   * The panel uses ExclusionMode.Normal rather than the Ignore that every
//     other fullscreen overlay uses, so it fills the usable area and leaves
//     the bar uncovered - the bar widget is where session progress is meant
//     to be visible.
Item {
  id: root

  // Injected by the shell's panel loader. omarchyPath must stay writable or
  // the injection TypeError aborts onLoaded and every summon silently no-ops.
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: (root.manifest && root.manifest.id)
    ? String(root.manifest.id) : "ribattrw.calm"
  // One state file, flat next to the other first-party state files so its
  // parent directory is guaranteed to exist. That matters: FileView.setText()
  // never creates missing parent directories, and a widget that starts
  // watching a file that does not exist yet never learns when it appears.
  readonly property string statePath: home + "/.local/state/omarchy/calm.json"
  readonly property string shellConfigPath: home + "/.config/omarchy/shell.json"
  readonly property string userAudioDir: home + "/.config/omarchy/calm/audio"

  readonly property string shippedAudioDir: {
    var resolved = Qt.resolvedUrl("assets/audio/").toString()
    if (resolved.indexOf("file://") === 0) {
      var path = decodeURIComponent(resolved.slice("file://".length))
      while (path.length > 1 && path.charAt(path.length - 1) === "/")
        path = path.slice(0, -1)
      return path
    }
    return home + "/.config/omarchy/plugins/ribattrw.calm/assets/audio"
  }

  property bool opened: false
  property bool active: false
  property string trigger: "manual"
  property string fontFamily: Style.font.menuFamily

  // Absolute wall-clock session bounds. Comparing Date.now() against these is
  // what makes a suspend mid-session resolve correctly on resume instead of
  // leaving a stale countdown lying about how long is left.
  property double startMs: 0
  property double endMs: 0
  property int sessionMinutes: Model.DEFAULT_MINUTES
  property double nowMs: Date.now()

  property bool configReady: false
  property string scheduleKey: ""
  property var cfg: Model.normaliseConfig(Model.defaultConfig())
  property var calmState: Model.emptyState()

  // Reminder scheduler state. Both are absolute deadlines, never a decremented
  // counter - see CalmModel.nextDeadline.
  property double nextDeadline: 0
  property double pendingUntil: 0
  property bool deadlineDecision: false

  property bool idleBusy: false
  property string idleReason: ""
  property string idleBuf: ""
  property bool idleAvailable: false
  property bool idleValue: false
  property bool idleEnabled: true

  property bool dndBusy: false
  property string dndBuf: ""
  // The same reader serves two questions, so it remembers which one it asked:
  // "save state for a session" versus "is the user asking for quiet?".
  property string dndMode: ""
  // True only when we observed DND off and switched it on ourselves - then we
  // owe the user their previous state back. Anything else (already on, or an
  // unreadable answer) leaves DND strictly alone.
  property bool dndOwed: false

  readonly property color foreground: Color.menu.text
  readonly property color dim: Color.muted

  // Design A from the review board: a paced disc inside a progress arc.
  readonly property real stage: Math.max(120, Math.min(panel.width, panel.height) * 0.60)
  readonly property real circleMax: stage * 0.70
  readonly property real circleMin: circleMax * 0.44

  // Where the breath actually is, straight off the wall clock.
  readonly property real targetFullness: root.active ? root.breath.fullness : 0

  // What the screen shows. A QML Timer is not synchronised to the display's
  // refresh, so driving the geometry straight off it steps the disc once per
  // tick and jitters whenever the tick phase drifts against the frame - that
  // is the stutter you can see at 20 ticks a second. Handing the value to a
  // Behavior instead lets the render loop re-aim it on every displayed frame,
  // so the disc is repositioned on vsync no matter how coarse the clock is.
  //
  // Linear, and deliberately longer than the 50 ms tick: each retarget is one
  // short straight segment between two points on the same cosine, and because
  // the animation is still in flight when the next target lands it never
  // settles and restarts from zero velocity - no per-tick hesitation.
  property real shownFullness: root.targetFullness
  Behavior on shownFullness {
    NumberAnimation { duration: 80; easing.type: Easing.Linear }
  }

  // Declared explicitly: without it the pacer disc binds to nothing and
  // renders at 0x0 - an invisible breathing visual.
  readonly property real circleSize:
    circleMin + (circleMax - circleMin) * shownFullness
  readonly property var breath: root.active
    ? Model.breathAt((root.nowMs - root.startMs) / 1000)
    : { label: "", fullness: 0, secsLeft: 0 }
  readonly property real progress: root.active
    ? Model.progressOf(root.startMs, root.endMs, root.nowMs)
    : 0

  function tint(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  // -------------------------------------------------------------------------
  // One config file: the widget's inline entry in shell.json.
  // -------------------------------------------------------------------------
  function applyShellConfig(raw) {
    var next = Model.configFromShell(raw, root.pluginId)
    var key = [next.reminders, next.reminderMinutes, next.dayStart, next.dayEnd].join("|")
    var scheduleChanged = key !== root.scheduleKey
    root.cfg = next
    root.configReady = true
    if (scheduleChanged) {
      root.scheduleKey = key
      resetSchedule()
    }
    if (root.active) runAudio(root.cfg.sound)
    // Cues disabled mid-session: stop the one in flight, too.
    if (!next.breathCues && cueProc.running) cueProc.running = false
  }

  function resetSchedule() {
    if (!root.cfg.reminders) {
      root.nextDeadline = 0
      root.pendingUntil = 0
      return
    }
    root.nextDeadline = Model.firstAllowedAtOrAfter(
      Date.now() + root.cfg.reminderMinutes * 60000,
      root.cfg.dayStart, root.cfg.dayEnd)
  }

  FileView {
    id: shellConfigFile
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyShellConfig(text())
    onFileChanged: reload()
    onLoadFailed: root.applyShellConfig("")
  }

  // -------------------------------------------------------------------------
  // Shared state file: the only bridge between the overlay and the bar widget.
  //
  // Written with FileView.setText() rather than a detached `sh -c` - the same
  // mechanism the first-party notifications and clipboard services use - so no
  // subprocess is spawned per write, and atomicWrites keeps a crash mid-write
  // from leaving a truncated file behind. This component is the sole writer,
  // so its own copy in memory is authoritative and it never needs to watch.
  // -------------------------------------------------------------------------
  function writeState(next) {
    root.calmState = next
    stateFile.setText(Model.stateJson(next))
  }

  FileView {
    id: stateFile
    path: root.statePath
    // The writer does not watch its own file: atomicWrites replaces the file,
    // which invalidates a watch on it. Change detection belongs to the widget's
    // directory watch instead.
    watchChanges: false
    atomicWrites: true
    printErrors: false
    // Nudge the bar widget only once the bytes are on disk: reloading here
    // would race the async save and hand the widget the previous state.
    onSaved: Quickshell.execDetached([
      root.omarchyPath + "/bin/omarchy-shell", "-q",
      "ribattrw.calm.widget", "sync"
    ])
    onLoaded: {
      root.calmState = Model.parseState(text())
      root.hintStateReady = true
      root.resumeAmbientOnce()
      root.maybeKeybindHint()
    }
    onLoadFailed: {
      root.calmState = Model.emptyState()
      root.hintStateReady = true
      root.resumeAmbientOnce()
      root.maybeKeybindHint()
    }
  }

  property bool ambientResumed: false
  function resumeAmbientOnce() {
    if (root.ambientResumed) return
    root.ambientResumed = true
    if (root.calmState.ambient && !root.active) runAudio(root.cfg.sound)
  }

  // -----------------------------------------------------------------------
  // One-time first-run hint for the Super+Alt+M keybind. The plugin cannot
  // register the binding itself (no install hooks, no manifest field), so
  // the README ships the exact line that adds it - and this fires exactly
  // once, only while the user's bindings.lua has no Calm binding yet. Both
  // inputs (state flag, binding present) must be read before deciding.
  // -----------------------------------------------------------------------
  property bool hintStateReady: false
  property bool hintBindReady: false
  property bool hintBindConfigured: false
  property bool hintChecked: false

  FileView {
    id: keybindFile
    path: root.home + "/.config/hypr/bindings.lua"
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.hintBindConfigured = Model.mentionsPlugin(text())
      root.hintBindReady = true
      root.maybeKeybindHint()
    }
    onLoadFailed: {
      // No bindings.lua at all: certainly no Calm binding yet.
      root.hintBindConfigured = false
      root.hintBindReady = true
      root.maybeKeybindHint()
    }
  }

  function maybeKeybindHint() {
    if (root.hintChecked || !root.hintStateReady || !root.hintBindReady) return
    root.hintChecked = true
    if (root.calmState.keybindHint) return
    if (!root.hintBindConfigured) {
      Quickshell.execDetached(Model.noticeCommand(
        root.omarchyPath,
        "Calm: one line to add Super+Alt+M",
        "Paste the single line from the Calm README (Keybinding) once - " +
        "then Super+Alt+M starts a breathing session."))
    }
    // Mark done either way: once checked, never re-checked on later starts.
    writeState(Model.withKeybindHint(root.calmState))
  }

  // -------------------------------------------------------------------------
  // Audio. This component is the sole owner of the players, so a session and
  // the standalone soundscape can never fight over two competing processes.
  //
  // `baseLayerOn` is the single layer-activity gate: the cicada layer and the
  // breath cues only ever run while a soundscape loop is meant to be playing
  // (sound=none stays full silence) and cues only while a session is active.
  // -------------------------------------------------------------------------
  property bool baseLayerOn: false

  function stopAudio() {
    root.baseLayerOn = false
    if (audioProc.running) audioProc.running = false
    if (cicadaProc.running) cicadaProc.running = false
  }

  function runLayer(proc, cmd) {
    if (proc.running) {
      proc.running = false
      Qt.callLater(function() {
        proc.command = cmd
        proc.running = true
      })
    } else {
      proc.command = cmd
      proc.running = true
    }
  }

  function runAudio(sound) {
    if (!sound || sound === "none" || sound === "") {
      stopAudio()
      return
    }
    root.baseLayerOn = true
    runLayer(audioProc, Model.audioCommand(
      sound, root.cfg.volume, root.userAudioDir, root.shippedAudioDir))
    // Second mpv for the cicada ambience layer: same script, same single-
    // owner lifecycle, its own gain (cicadaVolume) and client name so the two
    // streams stay separately addressable in wpctl. Only when cicadas are on
    // AND a soundscape is playing - never as a standalone sound.
    if (root.cfg.cicadas) {
      runLayer(cicadaProc, Model.audioCommand(
        "cicada", root.cfg.cicadaVolume, root.userAudioDir, root.shippedAudioDir,
        "omarchy-calm-cicadas"))
    } else if (cicadaProc.running) {
      cicadaProc.running = false
    }
  }

  Process { id: audioProc }
  Process { id: cicadaProc }

  // Breath cues: one owned pw-play process (not execDetached) so an in-flight
  // cue dies with teardown. `lastCueLabel` edge-detects the pacer label so a
  // cue fires exactly on the phase transition - never at open mid-phase, and
  // never twice for one phase.
  property string lastCueLabel: ""
  Process { id: cueProc }

  function fireBreathCue(label) {
    runLayer(cueProc, Model.cueCommand(
      label === "Breathe in" ? "breath-in" : "breath-out",
      root.cfg.breathVolume, root.userAudioDir, root.shippedAudioDir))
  }

  function toggleAmbient() {
    if (root.active) return
    var next = !root.calmState.ambient
    writeState(Model.withAmbient(root.calmState, next, root.cfg.sound))
    if (next) runAudio(root.cfg.sound)
    else stopAudio()
  }

  // -------------------------------------------------------------------------
  // Do not disturb: borrowed for the session, restored afterwards.
  // -------------------------------------------------------------------------
  function shellBin(name, args) {
    return [root.omarchyPath + "/bin/" + name].concat(args)
  }

  function runCapture(proc, bufProp, command) {
    if (proc.running) proc.running = false
    root[bufProp] = ""
    proc.command = command
    proc.running = true
  }

  function engageDnd() {
    root.dndMode = "session"
    root.dndBusy = true
    runCapture(dndReadProc, "dndBuf",
      shellBin("omarchy-shell", ["notifications", "dndState"]))
  }

  function releaseDnd() {
    if (!root.dndOwed) return
    root.dndOwed = false
    dndWriteProc.command = shellBin("omarchy-shell", ["notifications", "setDnd", "false"])
    dndWriteProc.running = true
  }

  Process {
    id: dndReadProc
    stdout: SplitParser { onRead: function(line) { root.dndBuf += String(line) } }
    onExited: function(code) {
      root.dndBusy = false
      var answer = root.dndBuf.trim()
      root.dndBuf = ""

      if (root.dndMode === "deadline") {
        // Quiet already means the user asked not to be interrupted: no heads-up.
        if (answer !== "on") root.issueHeadsUp()
        else root.deadlineDecision = false
        return
      }

      if (answer === "off") {
        root.dndOwed = true
        dndWriteProc.command = root.shellBin("omarchy-shell", ["notifications", "setDnd", "true"])
        dndWriteProc.running = true
      } else {
        // "on" means the user already asked for quiet; anything else means we
        // could not read it. Neither case is ours to change.
        root.dndOwed = false
      }
    }
  }
  Process { id: dndWriteProc }

  // -------------------------------------------------------------------------
  // Idle awareness comes from omarchy.idle (its own IPC target), not from a
  // poller we write. This is only ever consulted at a reminder deadline or
  // while a heads-up is waiting for a pause - never as a background watcher.
  // -------------------------------------------------------------------------
  function probeIdle(reason) {
    if (root.idleBusy) return
    root.idleBusy = true
    root.idleReason = reason
    runCapture(idleProc, "idleBuf",
      shellBin("omarchy-shell", ["idle", "status"]))
  }

  Process {
    id: idleProc
    stdout: SplitParser { onRead: function(line) { root.idleBuf += String(line) } }
    onExited: function(code) {
      root.idleBusy = false
      var raw = root.idleBuf.trim()
      root.idleBuf = ""
      var parsed = null
      try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
      if (parsed && typeof parsed === "object") {
        root.idleAvailable = true
        root.idleValue = parsed.idle === true
        root.idleEnabled = parsed.enabled !== false
      } else {
        // Unknown is treated as "assume active": better to nudge quietly than
        // to silently swallow reminders because an IPC call hiccupped.
        root.idleAvailable = false
        root.idleValue = false
        root.idleEnabled = true
      }
      root.handleIdle(root.idleReason)
    }
  }

  function handleIdle(reason) {
    if (reason === "deadline") {
      if (root.idleAvailable && root.idleEnabled && root.idleValue) {
        // Already away: never nag someone who is not there.
        root.deadlineDecision = false
        return
      }
      root.dndMode = "deadline"
      root.dndBusy = true
      runCapture(dndReadProc, "dndBuf",
        shellBin("omarchy-shell", ["notifications", "dndState"]))
      return
    }
    if (reason === "pending") {
      if (root.pendingUntil > 0 && root.idleEnabled && root.idleValue)
        startReminderSession()
    }
  }

  // -------------------------------------------------------------------------
  // The break-reminder scheduler.
  // -------------------------------------------------------------------------
  function schedulerInterval() {
    var now = Date.now()
    if (root.pendingUntil > now) return 5000          // waiting for a pause
    var target = root.nextDeadline
    if (target <= 0) return 60000
    var remain = target - now
    if (remain <= 0) return 500                       // overdue: act now
    if (remain > 61000) return remain - 60000         // wake ~1 min before it
    return Math.max(250, remain)                      // count the last minute down
  }

  function schedulerTick() {
    var now = Date.now()
    if (root.configReady && root.cfg.reminders && root.nextDeadline > 0) {
      if (root.pendingUntil > 0 && now >= root.pendingUntil)
        root.pendingUntil = 0

      if (root.pendingUntil > 0) {
        probeIdle("pending")
      } else if (now >= root.nextDeadline) {
        // Advance first: whatever the probes answer, the next heads-up is one
        // full interval away, so a suspended machine cannot replay a burst of
        // missed nudges when it wakes.
        root.nextDeadline = Model.nextDeadline(
          now, root.cfg.reminderMinutes * 60000, root.cfg.dayStart, root.cfg.dayEnd)
        if (Model.inAllowedHours(now, root.cfg.dayStart, root.cfg.dayEnd)
            && !root.deadlineDecision && !root.active) {
          root.deadlineDecision = true
          probeIdle("deadline")
        }
      }
    }
    schedTimer.interval = schedulerInterval()
    schedTimer.start()
  }

  Timer {
    id: schedTimer
    repeat: false
    interval: 5000
    onTriggered: root.schedulerTick()
  }

  function issueHeadsUp() {
    root.deadlineDecision = false
    if (root.active) return
    // Only arm the pause window when idle detection can actually report one;
    // with Stay Awake on there is no signal to wait for, so the heads-up
    // simply stays a click.
    if (root.idleEnabled)
      root.pendingUntil = Date.now() + Model.reminderGraceMs(root.cfg)
    Quickshell.execDetached(Model.headsUpCommand(
      root.omarchyPath, root.pluginId,
      "A breath, when you're ready",
      "Calm is here whenever you pause. Click to begin now."))
  }

  function startReminderSession() {
    root.pendingUntil = 0
    summonSelf(JSON.stringify({ trigger: "reminder" }))
  }

  function summonSelf(payloadJson) {
    if (root.shell && typeof root.shell.summon === "function") {
      root.shell.summon(root.pluginId, payloadJson)
      return
    }
    Quickshell.execDetached(shellBin("omarchy-shell",
      ["shell", "summon", root.pluginId, payloadJson]))
  }

  // -------------------------------------------------------------------------
  // Session lifecycle
  // -------------------------------------------------------------------------
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = String(payload.fontFamily)

    // A session that has just ended is still fading out; a summon inside that
    // window must cancel the pending hide or it would close the new session.
    hideTimer.stop()

    // A keypress during a running session should not restart the clock.
    if (root.active) {
      root.opened = true
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }

    var minutes = Number(payload.minutes)
    if (!isFinite(minutes) || minutes <= 0) minutes = root.cfg.minutes
    var sound = (payload.sound !== undefined && payload.sound !== null)
      ? String(payload.sound) : root.cfg.sound

    root.pendingUntil = 0
    root.deadlineDecision = false
    root.trigger = payload.trigger === "reminder" ? "reminder" : "manual"
    root.sessionMinutes = Math.round(Model.clamp(minutes, 1, 60))
    root.nowMs = Date.now()
    root.startMs = root.nowMs
    root.endMs = Model.sessionEndMs(root.startMs, root.sessionMinutes)
    root.active = true
    root.opened = true

    // Showing up is what keeps the day - so an early exit counts by
    // construction and no session can be failed.
    writeState(Model.withSession(
      Model.keepDay(root.calmState, Model.dayKey(new Date())),
      { startedAt: root.startMs, endsAt: root.endMs, sound: sound, trigger: root.trigger }))

    engageDnd()
    runAudio(sound)
    // First cue lands on the first phase *transition*, never mid-phase at open.
    root.lastCueLabel = ""
    sessionTick.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function teardown(completed) {
    if (!root.active) return
    var minutes = root.sessionMinutes
    root.active = false

    // DND goes back before any completion notice, or the notification we just
    // fire is one nobody will ever see.
    releaseDnd()
    if (cueProc.running) cueProc.running = false
    root.lastCueLabel = ""
    stopAudio()
    if (root.calmState.ambient) runAudio(root.cfg.sound)

    writeState(Model.withSession(root.calmState, null))

    if (completed) {
      Quickshell.execDetached(Model.noticeCommand(
        root.omarchyPath, "Session complete",
        "That's " + minutes + (minutes === 1 ? " minute" : " minutes") + " — today is kept."))
    }
  }

  function endSession(completed) {
    if (!root.active) return
    // Everything that has to happen *now* - DND back, player stopped, state
    // written, completion notice - happens in teardown, immediately. Only the
    // picture lingers, so the session dissolves instead of snapping off the
    // screen; hiding is deferred to hideTimer.
    teardown(completed)
    hideTimer.restart()
  }

  Timer {
    id: hideTimer
    interval: 750
    repeat: false
    onTriggered: root.hideSelf()
  }

  function hideSelf() {
    hideTimer.stop()
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  // The host calls close() on hide; also the safety net if the plugin is
  // disabled mid-session, so DND and the player never get stranded.
  function close() {
    hideTimer.stop()
    if (root.active) teardown(false)
    root.opened = false
  }

  Timer {
    id: sessionTick
    repeat: true
    interval: 50
    running: root.opened && root.active
    onTriggered: {
      root.nowMs = Date.now()
      if (root.active && root.nowMs >= root.endMs) root.endSession(true)
      // Breath cue fires on the breathAt label edge: same 50 ms tick as the
      // visual, so audio and pacer share one clock. Budget: <=50 ms tick
      // quantisation + ~13 ms pw-play start = ~63 ms worst case on the
      // 4000/6000 ms cycle. Gated on breathCues AND the layer-activity gate
      // (sound=none = silence; no cues outside a session - teardown flips
      // active off first, and endSession above already did if time ran out).
      if (root.active && root.cfg.breathCues && root.baseLayerOn) {
        var lb = root.breath.label
        if (root.lastCueLabel !== "" && lb !== root.lastCueLabel)
          root.fireBreathCue(lb)
        root.lastCueLabel = lb
      }
    }
  }

  // -------------------------------------------------------------------------
  // Scripting surface
  // -------------------------------------------------------------------------
  IpcHandler {
    target: "ribattrw.calm"

    function start(): void {
      root.summonSelf(JSON.stringify({ trigger: "manual" }))
    }

    function stop(): void {
      root.endSession(false)
    }

    function ambient(): void {
      root.toggleAmbient()
    }

    function sound(name: string): string {
      var next = String(name || "").trim()
      if (next) {
        if (root.active || root.calmState.ambient) root.runAudio(next)
        root.writeState(Model.withAmbient(root.calmState, root.calmState.ambient, next))
      }
      return root.calmState.sound || root.cfg.sound
    }

    // Fires one heads-up immediately - the reminder path is otherwise only
    // reachable by waiting out the configured interval.
    function nudge(): void {
      if (!root.active) root.issueHeadsUp()
    }

    function status(): string {
      return JSON.stringify({
        active: root.active,
        opened: root.opened,
        trigger: root.trigger,
        startMs: root.startMs,
        endMs: root.endMs,
        minutes: root.sessionMinutes,
        ambient: root.calmState.ambient,
        sound: root.calmState.sound || root.cfg.sound,
        keptToday: Model.isKept(root.calmState, Model.dayKey(new Date())),
        reminders: root.cfg.reminders,
        reminderMinutes: root.cfg.reminderMinutes,
        window: root.cfg.dayStart + "-" + root.cfg.dayEnd,
        nextDeadline: root.nextDeadline,
        pendingUntil: root.pendingUntil,
        idle: { available: root.idleAvailable, value: root.idleValue, enabled: root.idleEnabled },
        dndOwed: root.dndOwed
      })
    }
  }

  Component.onCompleted: {
    schedTimer.interval = schedulerInterval()
    schedTimer.start()
  }

  // -------------------------------------------------------------------------
  // The session surface
  // -------------------------------------------------------------------------
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-calm"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus:
      root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Respect other surfaces' exclusive zones so the bar stays uncovered and
    // the widget can show live progress while the session runs.
    exclusionMode: ExclusionMode.Normal

    // Fade rather than snap: the desktop comes back under a dissolve instead
    // of one hard cut, and the first open eases in the same way. The opacity
    // rides the render loop, so it is frame-paced even though the clock that
    // flips `active` is not.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.background
      opacity: root.active ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: 700; easing.type: Easing.InOutQuad }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
          root.endSession(false)
          event.accepted = true
        }
      }
    }

    // A fixed-size stage, so the labels underneath never move as the disc
    // breathes - a bobbing layout would defeat the calm.
    Column {
      anchors.centerIn: parent
      spacing: Style.space(30)
      opacity: root.active ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: 700; easing.type: Easing.InOutQuad }
      }

      Item {
        width: root.stage
        height: root.stage
        anchors.horizontalCenter: parent.horizontalCenter

        Canvas {
          id: ring
          anchors.fill: parent
          // Declared here so a change to the value actually re-triggers paint;
          // binding straight into onPaint would never fire again after the
          // first frame.
          property real progress: root.progress
          property int drawnArc: -1
          // Repaint only when the arc has moved about a pixel. It sweeps some
          // 2000 px over a whole session, so redrawing this canvas on every
          // clock tick mostly re-rasterises sub-pixel changes for nothing -
          // and once the step is one pixel wide the sweep is indistinguishable
          // from a continuous one, while the canvas goes quiet in between.
          onProgressChanged: {
            var cc = width / 2
            var lwq = Math.max(2, Style.space(3))
            var rq = cc - lwq / 2 - Style.space(2)
            var px = rq > 0 ? Math.round(progress * 2 * Math.PI * rq) : -1
            if (px !== drawnArc) { drawnArc = px; requestPaint() }
          }
          onVisibleChanged: if (visible) requestPaint()
          Component.onCompleted: requestPaint()

          onPaint: {
            var ctx = getContext("2d")
            var c = width / 2
            var lw = Math.max(2, Style.space(3))
            var r = c - lw / 2 - Style.space(2)
            if (r <= 0) return
            ctx.reset()
            ctx.lineCap = "round"
            ctx.lineWidth = lw

            ctx.strokeStyle = Qt.rgba(Color.muted.r, Color.muted.g, Color.muted.b, 0.55)
            ctx.beginPath()
            ctx.arc(c, c, r, 0, Math.PI * 2)
            ctx.stroke()

            var p = Math.max(0.001, Math.min(1, progress))
            ctx.strokeStyle = Color.accent
            ctx.beginPath()
            ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p)
            ctx.stroke()
          }
        }

        Rectangle {
          anchors.centerIn: parent
          width: root.circleSize
          height: root.circleSize
          radius: width / 2
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b,
                         0.16 + 0.16 * root.shownFullness)
          border.color: Color.accent
          border.width: Math.max(1.5, Style.space(2))
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.active
        text: root.breath.label.toLowerCase()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.active
        text: root.cfg.sound && root.cfg.sound !== "none"
          ? Model.soundLabel(root.cfg.sound) + " · esc to end — an early exit still counts"
          : "esc to end — an early exit still counts"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 26
      text: Model.BREATHING_NOTE_TEXT
      // Legibility fix (captain: "i cant read it"): was 11 px in muted
      // (#4b4e55 on #101315 ~= 2:1 contrast) - unreadable at sitting
      // distance. Now the palette's display size (24 px at base-size 12) in
      // the foreground text colour (~11:1 contrast). Still the bottom-edge
      // line, still clears after 20 s, still below the eyes' focus area.
      color: root.foreground
      font.family: "sans-serif"
      font.pixelSize: Style.font.display
      opacity: (root.active && Model.breathingNoteVisibleAt(root.nowMs - root.startMs)) ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: 1500; easing.type: Easing.InOutQuad }
      }
    }
  }
}
