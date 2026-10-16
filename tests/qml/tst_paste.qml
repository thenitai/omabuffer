import QtQuick
import QtQuick.Controls
import QtTest
import ClipboardTest 1.0
import "../.." as Plugin

TestCase {
  id: tests
  name: "BoundedPaste"
  visible: true
  width: 640
  height: 900
  when: Window.window !== null && Window.window.active
  property var composer
  property var setup
  readonly property string clipboardText: "clip 🌍\n<b>x</b>"

  Component { id: composerComponent; Plugin.Composer { width: 600 } }
  Component { id: setupComponent; Plugin.Setup { width: 600 } }
  Component { id: signalSpy; SignalSpy {} }

  function cleanup() {
    console.log("CASE " + qtest_results.functionName + ": " + (qtest_results.failed ? "FAIL" : "PASS"))
  }

  function cleanupTestCase() {
    console.log("RESULT " + qtest_results.passCount + " passed, " + qtest_results.failCount + " failed, " + qtest_results.skipCount + " skipped")
  }

  function init() {
    composer = createTemporaryObject(composerComponent, tests)
    verify(composer !== null)
    setup = createTemporaryObject(setupComponent, tests, { visible: false })
    verify(setup !== null)
  }

  function helper(editor) {
    for (var i = 0; i < editor.children.length; i++)
      if (typeof editor.children[i].request === "function") return editor.children[i]
    fail("No bounded paste helper attached to editor")
  }

  function prepare(editor) {
    editor.text = "before AFTER"
    editor.select(7, 12)
    editor.forceActiveFocus()
    verify(editor.activeFocus)
  }

  function setupEditor(shortcut) {
    composer.visible = false
    setup.visible = true
    if (!shortcut) return setup.keyField
    for (var i = 0; i < setup.children.length; i++)
      for (var j = 0; j < setup.children[i].children.length; j++) {
        var item = setup.children[i].children[j]
        if (item.placeholderText === "Disabled") return item
      }
    fail("Shortcut field missing")
  }

  function setupFields() {
    return [{ tag: "API key", shortcut: false }, { tag: "shortcut", shortcut: true }]
  }

  function test_no_automatic_clipboard_reads_data() {
    return [
      { tag: "hidden setup", visible: false, enabled: true },
      { tag: "visible setup", visible: true, enabled: true },
      { tag: "disabled setup", visible: true, enabled: false }
    ]
  }

  function test_no_automatic_clipboard_reads(data) {
    setup.visible = data.visible
    setup.enabled = data.enabled
    ClipboardProbe.offerText()
    wait(20)
    compare(ClipboardProbe.reads(), 0, "Clipboard changes must never fetch foreign text")
    // Creating fields while a foreign offer already exists must also be safe.
    var secondSetup = createTemporaryObject(setupComponent, tests, { visible: data.visible })
    verify(secondSetup !== null)
    wait(20)
    compare(ClipboardProbe.reads(), 0, "Field initialization must not fetch foreign text")
  }

  function test_keyboard_data() {
    return [
      { tag: "Ctrl+V", key: Qt.Key_V, mods: Qt.ControlModifier },
      { tag: "Super+V", key: Qt.Key_V, mods: Qt.MetaModifier },
      { tag: "Shift+Insert", key: Qt.Key_Insert, mods: Qt.ShiftModifier }
    ]
  }

  function test_keyboard(data) {
    var editor = composer.textAreaItem
    prepare(editor)
    keyClick(data.key, data.mods)
    verify(helper(editor).busy, "Paste gesture must use the helper")
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, "before " + clipboardText)
    compare(editor.textFormat, TextEdit.PlainText)
    compare(editor.cursorPosition, editor.length)
  }

  function test_middle_click() {
    var editor = composer.textAreaItem
    editor.text = ""
    mouseClick(editor, 20, 20, Qt.MiddleButton)
    verify(helper(editor).busy)
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, "primary")
  }

  function test_context_menu() {
    var editor = composer.textAreaItem
    prepare(editor)
    mouseClick(editor, 20, 20, Qt.RightButton)
    var menu = helper(editor).menu
    tryCompare(menu, "opened", true)
    var pasteItem = null
    for (var i = 0; i < menu.count; i++)
      if (menu.itemAt(i).text === "Paste") pasteItem = menu.itemAt(i)
    verify(pasteItem !== null)
    pasteItem.triggered()
    menu.close()
    verify(helper(editor).busy)
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, "before " + clipboardText)
  }

  function test_cancel_data() {
    return [
      { tag: "edit", change: function(editor) { editor.text = "new draft" } },
      { tag: "move cursor", change: function(editor) { editor.cursorPosition = 0 } },
      { tag: "change selection", change: function(editor) { editor.selectAll() } },
      { tag: "hide composer", change: function(editor) { tests.composer.visible = false } },
      { tag: "disable editor", change: function(editor) { editor.enabled = false } },
      { tag: "make read-only", change: function(editor) { editor.readOnly = true } }
    ]
  }

  function test_cancel(data) {
    var editor = composer.textAreaItem
    prepare(editor)
    keyClick(Qt.Key_V, Qt.ControlModifier)
    verify(helper(editor).busy)
    data.change(editor)
    var expected = editor.text
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, expected)
  }

  function test_repeated_paste_is_single_request() {
    var editor = composer.textAreaItem
    prepare(editor)
    keyClick(Qt.Key_V, Qt.ControlModifier)
    keyClick(Qt.Key_Insert, Qt.ShiftModifier)
    keyClick(Qt.Key_V, Qt.MetaModifier)
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, "before " + clipboardText)
  }

  function test_copy_cut_and_select_all_still_work() {
    var editor = composer.textAreaItem
    editor.text = "test text"
    editor.forceActiveFocus()
    keyClick(Qt.Key_A, Qt.ControlModifier)
    compare(editor.selectedText, "test text")
    keyClick(Qt.Key_X, Qt.ControlModifier)
    compare(editor.text, "")
    keyClick(Qt.Key_Z, Qt.ControlModifier)
    compare(editor.text, "test text")
    verify(!helper(editor).busy)
  }

  function test_setup_keyboard_data() {
    return [
      { tag: "API key Ctrl+V", key: Qt.Key_V, mods: Qt.ControlModifier },
      { tag: "API key Super+V", key: Qt.Key_V, mods: Qt.MetaModifier },
      { tag: "API key Shift+Insert", key: Qt.Key_Insert, mods: Qt.ShiftModifier },
      { tag: "shortcut Ctrl+V", key: Qt.Key_V, mods: Qt.ControlModifier, shortcut: true }
    ]
  }

  function test_setup_keyboard(data) {
    var editor = setupEditor(data.shortcut)
    prepare(editor)
    keyClick(data.key, data.mods)
    verify(helper(editor).busy)
    tryCompare(helper(editor), "busy", false)
    verify(editor.text.indexOf("before clip 🌍") === 0)
    verify(editor.text.indexOf("<b>x</b>") >= 0)
    verify(editor.text.indexOf("AFTER") < 0)
    // Replacing a selection is one undoable edit, including newline removal.
    keyClick(Qt.Key_Z, Qt.ControlModifier)
    compare(editor.text, "before AFTER")
  }

  function test_setup_editing_data() { return setupFields() }

  function test_setup_editing(data) {
    var editor = setupEditor(data.shortcut)
    var nativeField = findChild(editor, "clipboardSafeDisplay")
    verify(nativeField !== null)
    var spy = createTemporaryObject(signalSpy, tests, { target: nativeField, signalName: "readOnlyChanged" })
    editor.text = ""
    editor.forceActiveFocus()
    ClipboardProbe.offerText()
    keyClick(Qt.Key_A)
    keyClick(Qt.Key_B)
    keyClick(Qt.Key_C)
    compare(editor.text, "abc")
    keyClick(Qt.Key_Left, Qt.ShiftModifier)
    compare(editor.selectedText, "c")
    keyClick(Qt.Key_D)
    compare(editor.text, "abd")
    keyClick(Qt.Key_Backspace)
    compare(editor.text, "ab")
    keyClick(Qt.Key_Z, Qt.ControlModifier)
    compare(editor.text, "abd")
    keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
    compare(editor.text, "ab")
    keyClick(Qt.Key_Home)
    keyClick(Qt.Key_Delete)
    compare(editor.text, "b")
    compare(ClipboardProbe.reads(), 0, "Editing must not enable native clipboard reads")
    compare(nativeField.readOnly, true)
    compare(nativeField.canPaste, false)
    compare(spy.count, 0, "The native field must remain read-only throughout editing")
    if (!data.shortcut) {
      compare(nativeField.echoMode, TextInput.Password)
      verify(nativeField.displayText.indexOf("b") < 0, "Password text must never be displayed")
    }
  }

  function test_setup_copy_cut_data() { return setupFields() }

  function test_setup_copy_cut(data) {
    var editor = setupEditor(data.shortcut)
    editor.text = "secret"
    editor.forceActiveFocus()
    ClipboardProbe.offerText()
    keyClick(Qt.Key_A, Qt.ControlModifier)
    keyClick(Qt.Key_C, Qt.ControlModifier)
    compare(ClipboardProbe.text(), data.shortcut ? "secret" : "foreign clipboard text")
    ClipboardProbe.offerText()
    keyClick(Qt.Key_X, Qt.ControlModifier)
    compare(editor.text, "")
    compare(ClipboardProbe.text(), data.shortcut ? "secret" : "foreign clipboard text")
    keyClick(Qt.Key_Z, Qt.ControlModifier)
    compare(editor.text, "secret")
  }

  function test_setup_context_menu_data() { return setupFields() }

  function test_setup_context_menu(data) {
    var editor = setupEditor(data.shortcut)
    prepare(editor)
    ClipboardProbe.offerText()
    mouseClick(editor, 20, 15, Qt.RightButton)
    var menu = helper(editor).menu
    tryCompare(menu, "opened", true)
    compare(ClipboardProbe.reads(), 0, "Opening the menu must not inspect clipboard text")
    for (var i = 0; i < menu.count; i++) {
      var item = menu.itemAt(i)
      if (item.text === "Paste") item.triggered()
      if (!data.shortcut && (item.text === "Copy" || item.text === "Cut")) compare(item.enabled, false)
    }
    menu.close()
    verify(helper(editor).busy)
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, "before " + clipboardText.replace(/\n/g, ""))
    compare(ClipboardProbe.reads(), 0)
  }

  function test_setup_cancel_data() { return setupFields() }

  function test_setup_cancel(data) {
    var editor = setupEditor(data.shortcut)
    prepare(editor)
    keyClick(Qt.Key_V, Qt.ControlModifier)
    verify(helper(editor).busy)
    setup.visible = false
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, "before AFTER")
  }

  function test_setup_accept_data() { return setupFields() }

  function test_setup_accept(data) {
    var editor = setupEditor(data.shortcut)
    var spy = createTemporaryObject(signalSpy, tests, { target: setup, signalName: data.shortcut ? "shortcutApply" : "saved" })
    editor.text = data.shortcut ? "SUPER + ALT + B" : "example-key"
    editor.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], editor.text)
  }

  function test_setup_middle_click() {
    composer.visible = false
    setup.visible = true
    var editor = setup.keyField
    editor.text = ""
    mouseClick(editor, 20, 20, Qt.MiddleButton)
    verify(helper(editor).busy)
    tryCompare(helper(editor), "busy", false)
    compare(editor.text, "primary")
  }
}
