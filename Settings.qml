import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Ink.js" as Ink

// OmAnnotate settings: line width, time on screen, opacity and color. By
// default lines use the theme's accent and change with the theme; choosing a
// color of their own turns that off, so theme changes leave it alone. It is a
// normal floating window, so Super+W closes it like any other; it is drawn in
// the current theme's colors, and its swatches are the theme's own palette.
// Open it from OmAnnotate under Apps in the Omarchy menu or with
// `omarchy-shell omannotate settings`. Width, color and opacity change lines
// already on screen too; time on screen applies to lines finished afterwards.
// Everything is stored in this plugin's entry in ~/.config/omarchy/shell.json.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null
  property var service: null

  // True while the shell itself hides the window, so that is not reported back.
  property bool closingFromHost: false
  readonly property string themeColor: root.service ? root.service.themeColor : Ink.hex(Color.accent)
  property var draft: Ink.style({}, themeColor)

  // A theme change while the panel is open recolors the preview.
  onThemeColorChanged: {
    if (!root.draft) return  // Still being created.
    root.draft = Ink.style(Ink.stored(root.draft), root.themeColor)
    colorField.text = root.draft.color
  }

  // Theme switches reach the shell over IPC, so the palette file is read
  // again whenever the theme's main colors change.
  property string themeColors: ""
  readonly property string themeKey: String(Color.accent) + String(Color.foreground) + String(Color.background)
  onThemeKeyChanged: themeColorsFile.reload()
  readonly property var presets: Ink.themePalette(themeColors, themeColor)

  FileView {
    id: themeColorsFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.themeColors = text()
    onLoadFailed: root.themeColors = ""
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int windowWidth: Style.space(420)

  function open(payloadJson) {
    root.draft = Ink.style(root.service ? root.service.settings : {}, root.themeColor)
    colorField.text = root.draft.color
    root.closingFromHost = false
    window.visible = true
    // The window is created hidden, so focus is taken again once it is mapped,
    // and Hyprland is asked to focus it (it may already be open behind others).
    Qt.callLater(function() { if (window.visible) keys.forceActiveFocus() })
    raise.restart()
  }

  // For the README and store screenshots, while the window is open:
  // omarchy-shell omannotate-settings capture /path/to/settings.png
  // It saves only the window's own content, never the rest of the screen.
  IpcHandler {
    target: "omannotate-settings"

    function capture(path: string): string {
      if (!window.visible) return "open the settings first"
      keys.grabToImage(function(result) { result.saveToFile(path) }, Qt.size(keys.width * 2, keys.height * 2))
      return "ok"
    }
  }

  Timer {
    id: raise
    interval: 120
    onTriggered: if (window.visible) Quickshell.execDetached(["hyprctl", "eval",
      "hl.dispatch(hl.dsp.focus({ window = \"title:^OmAnnotate$\" }))"])
  }

  function close() {
    root.closingFromHost = true
    window.visible = false
    root.closingFromHost = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "omannotate")
    else close()
  }

  // Previews immediately; stores when `store` is true (slider released,
  // switch or swatch clicked, color entered). Choosing a color stops
  // following the theme.
  function change(key, value, store) {
    var next = Ink.stored(root.draft)
    next[key] = value
    if (key === "color") next.useThemeColor = false
    root.draft = Ink.style(next, root.themeColor)
    colorField.text = root.draft.color
    if (store && root.service) root.service.save(root.draft)
  }

  function restoreDefaults() {
    root.draft = Ink.style({}, root.themeColor)
    colorField.text = root.draft.color
    if (root.service) root.service.save(root.draft)
  }

  function formatted(value) {
    return Number.isInteger(value) ? String(value) : value.toFixed(1)
  }

  FloatingWindow {
    id: window
    title: "OmAnnotate"
    visible: false
    color: root.background
    implicitWidth: root.windowWidth
    implicitHeight: content.implicitHeight + root.contentMargin * 2
    // A fixed size, so Hyprland floats it like a dialog.
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)

    // Closed by the compositor (Super+W, the window's close request): tell
    // the shell, so the launcher opens it again next time.
    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "omannotate")
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      // Also paints the window's background into captures of this item.
      Rectangle {
        anchors.fill: parent
        color: root.background
      }

      ColumnLayout {
        id: content
        x: root.contentMargin
        y: root.contentMargin
        width: window.width - root.contentMargin * 2
        spacing: Style.space(14)

        Text {
          text: "OmAnnotate"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: "Hold Super+Ctrl and drag with the left mouse button to draw on any screen. "
            + "Lines stay for the time below after your last line, then fade out."
          wrapMode: Text.WordWrap
          color: root.foreground
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        // The theme's text and background colors: lines must read on both.
        Item {
          id: preview
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(72)
          clip: true

          Rectangle { width: parent.width / 2; height: parent.height; color: Color.foreground }
          Rectangle { x: parent.width / 2; width: parent.width / 2; height: parent.height; color: Color.background }
          // Frames the preview where the background half meets the window.
          Rectangle {
            z: 1
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.25)
          }

          readonly property var stroke: {
            var points = []
            for (var i = 0; i <= 40; i++)
              points.push([24 + i * (width - 48) / 40, height / 2 + height / 4 * Math.sin(i / 40 * 2 * Math.PI)])
            return { points: points, fadeStart: null }
          }
          readonly property var geo: Ink.geometry(stroke, root.draft)

          Item {
            x: preview.geo.x
            y: preview.geo.y
            width: preview.geo.width
            height: preview.geo.height
            opacity: root.draft.opacity / 100
            layer.enabled: true

            Shape {
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(0, 0, 0, Ink.OUTLINE_ALPHA)
                strokeWidth: root.draft.outline
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: preview.geo.path }
              }
              ShapePath {
                fillColor: "transparent"
                strokeColor: root.draft.color
                strokeWidth: root.draft.width
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: preview.geo.path }
              }
            }
          }
        }

        Repeater {
          model: [
            { key: "width", label: "Line width", unit: " px", step: 0.5 },
            { key: "hold", label: "Time on screen", unit: " s", step: 0.5 },
            { key: "opacity", label: "Opacity", unit: "%", step: 5 }
          ]

          delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(4)

            RowLayout {
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: modelData.label
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Text {
                text: root.formatted(root.draft[modelData.key]) + modelData.unit
                color: root.foreground
                opacity: 0.75
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            PanelSlider {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(24)
              minimum: Ink.LIMITS[modelData.key][0]
              maximum: Ink.LIMITS[modelData.key][1]
              step: modelData.step
              integer: modelData.key === "opacity"
              trackColor: Style.selectedFillFor(root.foreground, Color.accent)
              fillColor: root.foreground
              knobColor: root.foreground
              tickColor: root.background
              value: root.draft[modelData.key]
              onMoved: function(value) { root.change(modelData.key, value, false) }
              onReleased: function(value) { root.change(modelData.key, value, true) }
            }
          }
        }

        Toggle {
          Layout.fillWidth: true
          label: "Use theme color"
          description: root.draft.useThemeColor
            ? "Lines use the theme's accent and change with the theme."
            : "Lines keep the color below when the theme changes."
          checked: root.draft.useThemeColor
          foreground: root.foreground
          onClicked: root.change("useThemeColor", !root.draft.useThemeColor, true)
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Repeater {
            model: root.presets

            delegate: Rectangle {
              required property string modelData
              readonly property bool chosen: !root.draft.useThemeColor && root.draft.color === modelData
              Layout.preferredWidth: Style.space(22)
              Layout.preferredHeight: Style.space(22)
              radius: width / 2
              color: modelData
              border.width: chosen ? Math.max(2, Style.space(3)) : 1
              border.color: chosen ? root.foreground : Util.alpha(root.foreground, 0.35)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.change("color", modelData, true)
              }
            }
          }

          Item { Layout.fillWidth: true }

          TextField {
            id: colorField
            Layout.preferredWidth: Style.space(96)
            placeholderText: "#RRGGBB"
            foreground: root.foreground
            opacity: root.draft.useThemeColor ? 0.6 : 1
            font.family: Style.font.family
          }

          ColorEditGuard {
            target: colorField
            current: root.draft.color
            onCommitted: function(color) { root.change("color", color, true) }
          }
        }

        Toggle {
          Layout.fillWidth: true
          label: "Show in Omarchy menu"
          description: "OmAnnotate, with its logo, under Apps."
          checked: root.service ? root.service.menuShown : false
          foreground: root.foreground
          onClicked: if (root.service) root.service.setMenuShown(!root.service.menuShown)
        }

        // Why the app launcher could not be changed, if it could not.
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          text: root.service ? root.service.launcherMessage : ""
          wrapMode: Text.WordWrap
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(6)

          Button {
            text: "Restore defaults"
            foreground: root.foreground
            bordered: true
            onClicked: root.restoreDefaults()
          }

          Item { Layout.fillWidth: true }

          Button {
            text: "Done"
            foreground: root.foreground
            bordered: true
            onClicked: root.dismiss()
          }
        }
      }
    }
  }
}
