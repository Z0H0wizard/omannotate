import QtQuick
import "Ink.js" as Ink

// Commits the color typed into a text field only after the user really edited
// it. Qt also finishes editing when the field merely loses focus, and text set
// by the panel (opening it, a theme change) is not an edit, so neither may
// save a color or turn off "Use theme color". Invalid text is discarded and
// the field shows the current color again.
QtObject {
  id: guard

  // A TextInput-based field (Qt Quick Controls TextField or Omarchy's).
  property Item target: null
  // The color the field should show when not being edited.
  property string current: ""
  property bool edited: false

  signal committed(string color)

  property Connections watcher: Connections {
    target: guard.target

    function onTextEdited() {
      guard.edited = true
    }

    function onEditingFinished() {
      var color = guard.edited ? Ink.editedColor(guard.target.text, guard.current) : null
      guard.edited = false
      if (color) guard.committed(color)
      guard.target.text = guard.current
    }
  }
}
