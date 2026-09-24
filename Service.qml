import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Ink.js" as Ink
import "Launcher.js" as Launcher

// OmAnnotate: hold SUPER+CTRL and drag with the left mouse button to draw
// fading lines on any screen. hypr/omannotate.lua turns the click into
// Hyprland events; this service draws them in click-through overlay layers
// that exist only while lines are visible. Between lines it only reads
// Hyprland's event stream. It also keeps OmAnnotate, with its logo, under Apps
// in the Omarchy menu (see Launcher.js).
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omannotate"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string shortcutPath: decodeURIComponent(String(Qt.resolvedUrl("hypr/omannotate.lua")).replace(/^file:\/\//, ""))
  // Each service instance claims the shortcut under its own token, so the
  // instance a plugin reload replaces cannot switch the new one's off.
  readonly property string token: Date.now().toString(36) + Math.random().toString(36).slice(2, 8)

  // The release this code belongs to (kept equal to manifest.json by the tests).
  // After `omarchy plugin update`, omarchy-shell can keep running the code it
  // loaded before until it restarts, while the manifest it hands over is new.
  readonly property string codeVersion: "0.1.0"
  property bool restartNoticeSent: false

  onManifestChanged: checkCodeVersion()

  function checkCodeVersion() {
    var installed = root.manifest && root.manifest.version
    if (!installed || installed === root.codeVersion || root.restartNoticeSent) return
    root.restartNoticeSent = true
    console.warn("omannotate: " + installed + " is installed but " + root.codeVersion
      + " is still running; run omarchy restart shell")
    Quickshell.execDetached(["notify-send", "-a", "OmAnnotate", "OmAnnotate " + installed + " is installed",
      "Run omarchy restart shell to start using it."])
  }

  // This plugin's entry in shell.json, without its id.
  property var settings: ({})
  // The current theme's accent; lines follow it unless a color of their own was chosen.
  readonly property string themeColor: Ink.hex(Color.accent)
  readonly property var style: Ink.style(settings, themeColor)
  property var ink: Ink.createInk(Ink.DEFAULTS.hold)
  property real now: 0
  property int strokeCount: 0
  // Bumped whenever the lines change; the views below repaint from it.
  property int revision: 0

  onStyleChanged: {
    ink.hold = style.hold
    revision++
  }

  function handle(event) {
    var time = Date.now() / 1000
    if (event.type === "start") {
      ink.start(event.x, event.y, time)
    } else if (event.type === "move") {
      if (!ink.extend(event.x, event.y)) return
    } else if (!ink.end(time)) {
      return
    }
    update(true)
  }

  function clear() {
    if (ink.clear()) update(true)
  }

  // A still cursor or a line waiting to fade costs no repaint.
  function update(changed) {
    frame.stop()
    var time = Date.now() / 1000
    if (ink.prune(time)) changed = true
    if (ink.fading(time)) changed = true
    if (changed) {
      root.now = time
      root.strokeCount = ink.strokes.length
      root.revision++
    }
    var delay = ink.nextFrame(time)
    if (delay !== null) {
      frame.interval = Math.max(1, Math.ceil(delay * 1000))
      frame.start()
    }
  }

  Timer {
    id: frame
    repeat: false
    onTriggered: root.update(false)
  }

  // ------------------------------------------------------------ settings

  function readSettings(text) {
    var entry = null
    try {
      var config = JSON.parse(text || "{}")
      var plugins = Array.isArray(config.plugins) ? config.plugins : []
      for (var i = 0; i < plugins.length; i++)
        if (plugins[i] && plugins[i].id === root.pluginId) entry = plugins[i]
    } catch (e) {
      // A half-written or hand-broken file keeps the previous settings.
      console.warn("omannotate: could not read " + root.configPath + ": " + e)
      return
    }
    root.settings = entry || ({})
    if (!root.settingsLoaded) {
      root.settingsLoaded = true
      root.applyLauncher(root.menuShown)
    }
  }

  // Called by Settings.qml with a style. Values are clamped before they are stored.
  function save(lineStyle) {
    var entry = Ink.stored(Ink.style(Ink.stored(lineStyle), root.themeColor))
    if (root.settings.menu !== undefined) entry.menu = root.settings.menu
    store(entry)
  }

  function store(entry) {
    root.settings = entry
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.pluginId, entry)
  }

  property bool settingsLoaded: false

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readSettings(text())
  }

  // ------------------------------------------------------------ menu

  // OmAnnotate under Apps in the Omarchy menu, with its logo: links into this
  // folder made by bin/omannotate-launcher, so removing the plugin removes the
  // launcher too. Set up on every start unless turned off in the settings.
  readonly property bool menuShown: root.settings.menu !== false
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
  readonly property string launcherTool: decodeURIComponent(String(Qt.resolvedUrl("bin/omannotate-launcher")).replace(/^file:\/\//, ""))
  // Empty when all is well; otherwise shown in the settings panel.
  property string launcherMessage: ""
  property bool launcherWanted: true

  function applyLauncher(shown) {
    root.launcherWanted = shown
    if (launcher.running) return  // Its exit applies the latest choice.
    launcher.command = [root.launcherTool, shown ? "install" : "remove"]
    launcher.running = true
  }

  Process {
    id: launcher
    stderr: StdioCollector { id: launcherErrors }
    onExited: function(exitCode) {
      var detail = String(launcherErrors.text || "").trim()
      root.launcherMessage = exitCode === 0 ? "" : (detail || "OmAnnotate could not update its app launcher.")
      if (exitCode !== 0) console.warn("omannotate: " + root.launcherMessage)
      if (launcher.command[1] !== (root.launcherWanted ? "install" : "remove")) root.applyLauncher(root.launcherWanted)
    }
  }

  // From Settings.qml and `set menu`; stored, so a restart keeps the choice.
  function setMenuShown(shown) {
    var entry = JSON.parse(JSON.stringify(root.settings))
    entry.menu = shown
    store(entry)
    root.applyLauncher(shown)
  }

  // ------------------------------------------------------------ shortcut

  function luaString(value) {
    return JSON.stringify(String(value))
  }

  function claimShortcut() {
    claim.command = ["hyprctl", "eval",
      "dofile(" + luaString(root.shortcutPath) + "); omannotate.activate(" + luaString(root.token) + ")"]
    claim.running = true
  }

  Process {
    id: claim
    stdout: StdioCollector {
      onStreamFinished: {
        var reply = String(text || "").trim()
        if (reply !== "ok") console.warn("omannotate: the SUPER+CTRL+drag shortcut did not load: " + reply)
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") {
        // A reload drops runtime binds and the line being drawn with them.
        if (root.ink.end(Date.now() / 1000)) root.update(true)
        root.claimShortcut()
        return
      }
      var parsed = Ink.parse(event.name, event.data)
      if (parsed) root.handle(parsed)
    }
  }

  Component.onCompleted: {
    claimShortcut()
    checkCodeVersion()
  }
  Component.onDestruction: {
    Quickshell.execDetached(["hyprctl", "eval",
      "if omannotate then omannotate.deactivate(" + luaString(root.token) + ") end"])
    // Removes the launcher links if the plugin folder is gone a moment later.
    Quickshell.execDetached(Launcher.cleanupCommand(root.dataHome))
  }

  // ------------------------------------------------------------ drawing

  Variants {
    model: root.strokeCount > 0 ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: overlay
        required property var modelData

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omannotate"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Visual only: an empty input region never takes a click from the desktop.
        mask: Region {}

        Repeater {
          model: root.strokeCount

          delegate: Item {
            id: line
            required property int index

            readonly property var stroke: root.revision >= 0 ? root.ink.strokes[index] : null
            // Tied to the revision: a growing line is still the same object.
            readonly property var geo: root.revision >= 0 && stroke ? Ink.geometry(stroke, root.style) : null
            readonly property real fade: stroke && root.revision >= 0 ? root.ink.alpha(stroke, root.now) : 0
            readonly property bool onScreen: geo !== null
              && geo.x < overlay.modelData.x + overlay.modelData.width && geo.x + geo.width > overlay.modelData.x
              && geo.y < overlay.modelData.y + overlay.modelData.height && geo.y + geo.height > overlay.modelData.y

            visible: onScreen && fade > 0
            x: geo ? geo.x - overlay.modelData.x : 0
            y: geo ? geo.y - overlay.modelData.y : 0
            width: geo ? geo.width : 0
            height: geo ? geo.height : 0
            opacity: fade * root.style.opacity / 100
            // Drawn as one layer, so the dark edge never shows through the
            // fading color. The layer is only as large as the line.
            layer.enabled: visible

            Shape {
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(0, 0, 0, Ink.OUTLINE_ALPHA)
                strokeWidth: root.style.outline
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: line.geo ? line.geo.path : "" }
              }

              ShapePath {
                fillColor: "transparent"
                strokeColor: root.style.color
                strokeWidth: root.style.width
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: line.geo ? line.geo.path : "" }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ IPC

  IpcHandler {
    target: "omannotate"

    function status(): string {
      return JSON.stringify({
        lines: root.ink.strokes.length,
        drawing: root.ink.drawing !== null,
        width: root.style.width,
        hold: root.style.hold,
        color: root.style.color,
        useThemeColor: root.style.useThemeColor,
        opacity: root.style.opacity,
        menu: root.menuShown,
        launcherMessage: root.launcherMessage,
        version: (root.manifest && root.manifest.version) || "",
        code: root.codeVersion
      })
    }
    function clear(): string { root.clear(); return "ok" }
    // omarchy-shell omannotate set <width|hold|opacity|color|useThemeColor|menu> <value>
    function set(key: string, value: string): string {
      if (key === "menu") {
        root.setMenuShown(value === "true")
        return "ok"
      }
      var next = Ink.stored(root.style)
      if (key === "width" || key === "hold" || key === "opacity") next[key] = Number(value)
      else if (key === "useThemeColor") next[key] = value === "true"
      else if (key === "color") {
        if (!Ink.isColor(value)) return "color must be #RRGGBB"
        next.color = value
        next.useThemeColor = false
      } else return "unknown setting: " + key
      root.save(Ink.style(next, root.themeColor))
      return JSON.stringify(Ink.stored(root.style))
    }
    // Opens the settings window, or brings it forward if it is already open.
    function settings(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
  }
}
