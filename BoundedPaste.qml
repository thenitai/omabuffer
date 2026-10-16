import QtQuick
import QtQuick.Controls
import Quickshell.Io

// Put inside an editor, forward its Keys here and replace its ContextMenu.
// Never ask Qt to read foreign clipboard data in the persistent shell.
Item {
  id: paste
  required property var editor
  anchors.fill: parent
  property bool busy: false
  readonly property alias menu: editMenu
  property bool cancelled: false
  property bool applying: false
  property string originalText: ""
  property int selectionStart: 0
  property int selectionEnd: 0
  property int cursorPosition: 0
  signal failed(string message)

  function request(primary) {
    if (busy || reader.running || !editor.enabled || !editor.visible || editor.readOnly) return
    cancelled = false
    originalText = editor.text
    selectionStart = editor.selectionStart
    selectionEnd = editor.selectionEnd
    cursorPosition = editor.cursorPosition
    var script = decodeURIComponent(Qt.resolvedUrl("scripts/read-clipboard.py").toString().replace(/^file:\/\//, ""))
    reader.command = ["/usr/bin/python3", "-I", script, primary ? "primary" : "clipboard"]
    busy = true
    watchdog.restart()
    reader.running = true
  }

  function cancel() {
    if (!busy || applying) return
    cancelled = true
    if (reader.running) reader.signal(15)
  }

  Keys.onPressed: function(event) {
    if (event.matches(StandardKey.Paste) || event.key === Qt.Key_Paste
        || (event.key === Qt.Key_V && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)))
        || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
      event.accepted = true
      if (!event.isAutoRepeat) paste.request(false)
    }
  }

  // Consume the press AND release so TextEdit/TextInput cannot paste primary
  // selection through their native middle-button handlers.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    onClicked: function(mouse) {
      if (paste.busy || paste.editor.readOnly) return
      paste.editor.cursorPosition = paste.editor.positionAt(mouse.x, mouse.y)
      paste.editor.forceActiveFocus()
      paste.request(true)
    }
  }

  Connections {
    target: paste.editor
    function onTextChanged() { paste.cancel() }
    function onCursorPositionChanged() { paste.cancel() }
    function onSelectionStartChanged() { paste.cancel() }
    function onSelectionEndChanged() { paste.cancel() }
    function onVisibleChanged() { if (!paste.editor.visible) paste.cancel() }
    function onEnabledChanged() { if (!paste.editor.enabled) paste.cancel() }
    function onReadOnlyChanged() { if (paste.editor.readOnly) paste.cancel() }
  }

  Connections {
    target: paste.Window.window
    function onVisibleChanged() { if (!paste.Window.window.visible) paste.cancel() }
  }

  Process {
    id: reader
    stdout: StdioCollector { id: result; waitForEnd: true }
    onExited: function(code) {
      watchdog.stop()
      paste.busy = false
      var original = paste.originalText
      paste.originalText = ""
      if (paste.cancelled || !paste.editor.enabled || !paste.editor.visible || paste.editor.readOnly) return
      if (code !== 0) {
        paste.failed(code === 124 ? "Clipboard read timed out after 2 seconds."
          : code === 125 ? "Clipboard text exceeds the 64 KiB limit. Copy a smaller selection."
          : "Could not read clipboard text. Copy some text and try again.")
        return
      }
      if (!result.text || paste.editor.text !== original
          || paste.editor.cursorPosition !== paste.cursorPosition
          || paste.editor.selectionStart !== paste.selectionStart
          || paste.editor.selectionEnd !== paste.selectionEnd) return
      paste.applying = true
      paste.editor.remove(paste.selectionStart, paste.selectionEnd)
      paste.editor.insert(paste.selectionStart, result.text)
      paste.editor.cursorPosition = paste.selectionStart + result.text.length
      paste.editor.forceActiveFocus()
      paste.applying = false
    }
  }

  // Covers failure to start the system interpreter as well as helper startup.
  Timer {
    id: watchdog
    interval: 3000
    onTriggered: {
      var wasCancelled = paste.cancelled
      paste.cancel()
      paste.busy = false
      paste.originalText = ""
      if (!wasCancelled) paste.failed("Clipboard reader did not finish. Try copying the text again.")
    }
  }

  // Qt's default editing menu calls native paste(). Do not query canPaste:
  // text availability is determined by the isolated reader after the gesture.
  Menu {
    id: editMenu
    MenuItem {
      text: "Undo"
      enabled: !paste.editor.readOnly && paste.editor.canUndo
      onTriggered: paste.editor.undo()
    }
    MenuItem {
      text: "Redo"
      enabled: !paste.editor.readOnly && paste.editor.canRedo
      onTriggered: paste.editor.redo()
    }
    MenuSeparator {}
    MenuItem {
      text: "Cut"
      enabled: !paste.editor.readOnly && paste.editor.selectedText.length > 0
        && (paste.editor.echoMode === undefined || paste.editor.echoMode === TextInput.Normal)
      onTriggered: paste.editor.cut()
    }
    MenuItem {
      text: "Copy"
      enabled: paste.editor.selectedText.length > 0
        && (paste.editor.echoMode === undefined || paste.editor.echoMode === TextInput.Normal)
      onTriggered: paste.editor.copy()
    }
    MenuItem {
      text: "Paste"
      enabled: !paste.busy && !paste.editor.readOnly
      onTriggered: paste.request(false)
    }
    MenuItem {
      text: "Delete"
      enabled: !paste.editor.readOnly && paste.editor.selectedText.length > 0
      onTriggered: paste.editor.remove(paste.editor.selectionStart, paste.editor.selectionEnd)
    }
    MenuSeparator {}
    MenuItem {
      text: "Select all"
      enabled: paste.editor.length > 0
      onTriggered: paste.editor.selectAll()
    }
  }
}
