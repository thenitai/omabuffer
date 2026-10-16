import QtQuick
import QtQuick.Controls as Controls
import qs.Ui

// TextInput in Qt 6.11.2 fetches foreign text on clipboard changes, even when
// hidden or disabled. Keep the native field permanently read-only: it supplies
// layout, password masking, selection and navigation, but never clipboard reads.
// These settings accept direct keystrokes; paste is supplied by BoundedPaste.
FocusScope {
  id: field

  implicitHeight: display.implicitHeight
  implicitWidth: display.implicitWidth
  activeFocusOnTab: true

  property alias text: display.text
  property alias font: display.font
  property alias color: display.color
  property alias placeholderText: display.placeholderText
  property alias password: display.password
  property Controls.Menu editMenu
  property alias cursorPosition: display.cursorPosition
  readonly property alias selectionStart: display.selectionStart
  readonly property alias selectionEnd: display.selectionEnd
  readonly property alias selectedText: display.selectedText
  readonly property alias length: display.length
  readonly property alias echoMode: display.echoMode
  property bool readOnly: false // Logical editing state; never changes display.readOnly.
  property var undoStates: []
  property var redoStates: []
  property bool changing: false
  readonly property bool canUndo: !readOnly && undoStates.length > 0
  readonly property bool canRedo: !readOnly && redoStates.length > 0
  signal accepted()

  onTextChanged: if (!changing) { undoStates = []; redoStates = [] }

  function snapshot() {
    return { text: text, cursor: cursorPosition, start: selectionStart, end: selectionEnd }
  }

  function restore(state) {
    changing = true
    display.text = state.text
    display.select(state.cursor === state.start ? state.end : state.start, state.cursor)
    changing = false
  }

  function replace(start, end, value) {
    if (readOnly || !enabled) return
    // Match a single-line field and keep its existing 32767-character limit.
    value = value.replace(/[\r\n\u2028\u2029]/g, "")
    value = value.slice(0, display.maximumLength - (length - (end - start)))
    if (start === end && value === "") return
    undoStates = undoStates.slice(-31).concat([snapshot()])
    redoStates = []
    changing = true
    // Assign the complete value so password text is never briefly echoed by
    // TextInput.insert()'s platform password-mask delay.
    display.text = text.slice(0, start) + value + text.slice(end)
    display.cursorPosition = start + value.length
    changing = false
  }

  function insert(position, value) { replace(position, position, value) }
  function remove(start, end) { replace(start, end, "") }
  function clear() { replace(0, length, "") }
  function select(start, end) { display.select(start, end) }
  function selectAll() { display.selectAll() }
  function positionAt(x, y) { return display.positionAt(x, y) }
  function copy() { display.copy() } // Native password mode refuses to export secrets.
  function cut() {
    if (readOnly || !enabled) return
    copy()
    remove(selectionStart, selectionEnd)
  }
  function undo() {
    if (!canUndo) return
    redoStates = redoStates.concat([snapshot()])
    var previous = undoStates[undoStates.length - 1]
    undoStates = undoStates.slice(0, -1)
    restore(previous)
  }
  function redo() {
    if (!canRedo) return
    undoStates = undoStates.concat([snapshot()])
    var next = redoStates[redoStates.length - 1]
    redoStates = redoStates.slice(0, -1)
    restore(next)
  }

  function adjacent(position, backwards, word) {
    if (word) {
      var part = backwards ? text.slice(0, position) : text.slice(position)
      var match = backwards ? part.match(/\S+\s*$|\s+$/) : part.match(/^\s*\S+|^\s+/)
      return position + (backwards ? -1 : 1) * (match ? match[0].length : 0)
    }
    var next = Math.max(0, Math.min(length, position + (backwards ? -1 : 1)))
    // Never split a UTF-16 surrogate pair when deleting a character.
    if (next > 0 && next < length && /[\uD800-\uDBFF]/.test(text[next - 1])
        && /[\uDC00-\uDFFF]/.test(text[next])) next += backwards ? -1 : 1
    return next
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    var command = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!readOnly) field.accepted()
    } else if (event.matches(StandardKey.SelectAll) || (command && event.key === Qt.Key_A)) {
      selectAll()
    } else if (event.matches(StandardKey.Copy) || (command && event.key === Qt.Key_C)) {
      copy()
    } else if (event.matches(StandardKey.Cut) || (command && event.key === Qt.Key_X)) {
      cut()
    } else if (event.matches(StandardKey.Redo) || (command && event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier))) {
      redo()
    } else if (event.matches(StandardKey.Undo) || (command && event.key === Qt.Key_Z)) {
      undo()
    } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
      var backwards = event.key === Qt.Key_Backspace
      var target = adjacent(cursorPosition, backwards, !!command)
      remove(selectionStart !== selectionEnd ? selectionStart : Math.min(cursorPosition, target),
             selectionStart !== selectionEnd ? selectionEnd : Math.max(cursorPosition, target))
    } else if (!command && !(event.modifiers & Qt.AltModifier) && event.text.length > 0
               && !/[\x00-\x1f\x7f]/.test(event.text)) {
      replace(selectionStart, selectionEnd, event.text)
    } else {
      // The read-only native field handles arrows, Home/End and selection.
      return
    }
    event.accepted = true
  }

  TextField {
    id: display
    objectName: "clipboardSafeDisplay"
    anchors.fill: parent
    focus: true
    activeFocusOnTab: false
    readOnly: true // Security boundary: never toggle this, including during edits.
    selectByMouse: true
    cursorVisible: activeFocus && !field.readOnly
    Controls.ContextMenu.menu: field.editMenu
    Keys.priority: Keys.BeforeItem
    Keys.forwardTo: [field]
  }
}
