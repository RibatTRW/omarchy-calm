pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "CalmModel.js" as Model

// The Calm bar widget: one click starts a session, one ring carries every
// state the plugin has to show. It deliberately has no panel and no settings
// popup - there is nothing to configure at the bar, because the whole point
// is that there are no decisions to make.
//
//   left click    start a session immediately
//   middle click  toggle the standalone ambient loop
//
// Everything it displays comes from the state file the overlay writes, so the
// widget never has to reach into another plugin's service object and keeps
// working while a session runs fullscreen.
BarWidget {
  id: root
  moduleName: "ribattrw.calm"

  readonly property string pluginId: root.moduleName
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string statePath:
    Quickshell.env("HOME") + "/.local/state/omarchy/calm.json"
  readonly property string stateDir:
    Quickshell.env("HOME") + "/.local/state/omarchy"

  property var calmState: Model.emptyState()
  property double nowMs: Date.now()

  readonly property bool sessionActive: !!calmState.session
  readonly property bool keptToday:
    Model.isKept(calmState, Model.dayKey(new Date()))
  readonly property bool ambient: calmState.ambient === true
  readonly property real progress: sessionActive
    ? Model.progressOf(calmState.session.startedAt, calmState.session.endsAt, nowMs)
    : 0

  // The bar keeps a far coarser clock than the breathing animation - the arc
  // only has to sweep - and the Behavior below interpolates between these
  // samples, so the sweep stays continuous at display frame rate instead of
  // jumping once a second.
  Timer {
    running: root.sessionActive
    repeat: true
    interval: 500
    onTriggered: root.nowMs = Date.now()
  }

  // Change detection watches the *directory*, not the file, for two reasons
  // first-party bar code also relies on: a watch established on a file that
  // does not exist yet never fires when it later appears, and the writer uses
  // atomicWrites (a rename) which invalidates a watch pinned to the old file.
  // The directory always exists, so neither case can strand the widget.
  FileView {
    id: stateDirWatch
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.calmState = Model.parseState(text())
      console.log("calm widget: state loaded kept=" +
        Model.isKept(root.calmState, Model.dayKey(new Date())) +
        " session=" + (root.calmState.session !== null))
    }
    onLoadFailed: root.calmState = Model.emptyState()
  }

  // The writer nudges this after every save. It is the backstop first-party
  // bar/Bar.qml uses for the same reason: a directory watch can go quiet, and
  // a widget that misses one update stays visibly wrong until the next one.
  // The nudge arrives after the save completes, so there is no read-before-
  // write race.
  IpcHandler {
    target: "ribattrw.calm.widget"

    function sync(): void {
      stateFile.reload()
    }
  }

  function tooltipText() {
    var parts = ["Calm"]
    parts.push(root.sessionActive
      ? "breathing — esc ends it, it still counts"
      : "click to breathe")
    if (root.keptToday) parts.push("today kept")
    if (root.ambient) parts.push("ambient playing")
    return parts.join(" · ")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltipText()

    iconComponent: Component {
      Item {
        // The three states share one glyph so the widget never changes size
        // or shifts its neighbours in the bar:
        //   idle    dim ring, dim core, and a quiet dot once today is kept
        //   session accent arc filling the same ring, accent core
        Canvas {
          id: glyph
          anchors.centerIn: parent
          width: Style.space(14)
          height: Style.space(14)

          property real p: root.progress
          // Longer than the 500 ms sample interval and linear, so the arc is
          // always still travelling towards the last sample when the next one
          // arrives - it glides instead of stepping, and never restarts from
          // rest mid-sweep.
          Behavior on p {
            NumberAnimation { duration: 550; easing.type: Easing.Linear }
          }
          property bool running: root.sessionActive
          property color accent: Color.accent
          property color muted: Color.muted

          onPChanged: requestPaint()
          onRunningChanged: requestPaint()
          onAccentChanged: requestPaint()
          onMutedChanged: requestPaint()
          Component.onCompleted: requestPaint()

          onPaint: {
            var ctx = getContext("2d")
            var c = width / 2
            var r = c - 1.6
            if (r <= 0) return
            ctx.reset()
            ctx.lineCap = "round"

            ctx.strokeStyle = Qt.rgba(muted.r, muted.g, muted.b, 0.75)
            ctx.lineWidth = 1.4
            ctx.beginPath()
            ctx.arc(c, c, r, 0, Math.PI * 2)
            ctx.stroke()

            if (running) {
              var frac = Math.max(0.004, Math.min(1, p))
              ctx.strokeStyle = accent
              ctx.lineWidth = 2.2
              ctx.beginPath()
              ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac)
              ctx.stroke()
            }

            ctx.fillStyle = running
              ? Qt.rgba(accent.r, accent.g, accent.b, 0.95)
              : Qt.rgba(muted.r, muted.g, muted.b, 0.85)
            ctx.beginPath()
            ctx.arc(c, c, Math.max(1.6, r * 0.40), 0, Math.PI * 2)
            ctx.fill()
          }
        }

        // The only streak surface in the whole plugin: one dot for "today is
        // kept". No count, no number, nothing to review.
        Rectangle {
          visible: root.keptToday
          anchors.top: parent.top
          anchors.right: parent.right
          width: Style.space(5)
          height: width
          radius: width / 2
          color: Color.accent
          border.width: 1.5
          border.color: Color.bar.background
        }
      }
    }

    onPressed: function(button) {
      if (button === Qt.MiddleButton) {
        // The overlay owns the player, so the toggle goes through its IPC
        // target rather than starting a second competing process here.
        Quickshell.execDetached([
          root.omarchyPath + "/bin/omarchy-shell", "-q",
          root.pluginId, "ambient"
        ])
        return
      }
      if (button === Qt.LeftButton) {
        Quickshell.execDetached([
          root.omarchyPath + "/bin/omarchy-shell",
          "shell", "summon", root.pluginId, "{}"
        ])
      }
    }
  }
}
