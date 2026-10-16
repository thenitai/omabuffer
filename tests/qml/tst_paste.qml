import QtQuick
import QtQuick.Controls
import QtTest
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
    composer.visible = false
    setup.visible = true
    var editor = setup.keyField
    if (data.shortcut) {
      // The shortcut input is the first TextField in the settings row.
      for (var i = 0; i < setup.children.length; i++)
        for (var j = 0; j < setup.children[i].children.length; j++) {
          var item = setup.children[i].children[j]
          if (item.placeholderText === "Disabled") editor = item
        }
    }
    prepare(editor)
    keyClick(data.key, data.mods)
    verify(helper(editor).busy)
    tryCompare(helper(editor), "busy", false)
    verify(editor.text.indexOf("before clip 🌍") === 0)
    verify(editor.text.indexOf("<b>x</b>") >= 0)
    verify(editor.text.indexOf("AFTER") < 0)
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
