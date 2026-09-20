import QtQuick
import qs.Commons
import qs.Ui

// First-run account setup: Buffer API key, verified with a live `buffer
// account` CLI call before anything is persisted. The global shortcut is
// configured here too.

Column {
  id: setup

  spacing: Style.space(16)

  property color foreground: Color.menu.text
  property color errorColor: Color.urgent
  property string fontFamily: Style.font.menuFamily
  property int contentSpacing: Style.space(16)
  property bool busy: false
  property bool canGoBack: false
  property bool signedIn: false
  property bool cliMissing: false
  property string currentKey: ""
  property string shortcutValue: ""
  property bool shortcutBusy: false
  property bool shortcutOk: true
  property string shortcutMessage: ""
  property string channelCacheText: ""
  property bool channelRefreshBusy: false
  property string statusText: ""
  property bool statusError: false

  signal saved(string apiKey)
  signal shortcutApply(string value)
  signal channelRefreshRequested()
  signal backRequested()
  signal dismissRequested()

  property alias keyField: keyField

  function clearStatus() {
    statusText = ""
  }

  function prefill() {
    shortcutField.text = setup.shortcutValue
    keyField.text = setup.currentKey
  }

  onVisibleChanged: if (visible) prefill()

  Text {
    text: setup.signedIn ? "Buffer settings" : "Sign in to Buffer"
    color: setup.foreground
    font.family: setup.fontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
  }

  // ---- global shortcut ------------------------------------------------------

  Text {
    text: "Global shortcut"
    color: setup.foreground
    font.family: setup.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Row {
    width: parent.width
    spacing: setup.contentSpacing

    TextField {
      id: shortcutField
      width: parent.width - shortcutApplyButton.width - parent.spacing
      enabled: !setup.shortcutBusy
      placeholderText: "Disabled"
      color: setup.foreground
      font.family: setup.fontFamily
      onAccepted: setup.shortcutApply(text)
      Keys.onEscapePressed: function(event) {
        if (!setup.shortcutBusy) setup.dismissRequested()
        event.accepted = true
      }
    }

    Button {
      id: shortcutApplyButton
      height: Style.space(30)
      text: setup.shortcutBusy ? "Applying…" : "Apply"
      bordered: true
      enabled: !setup.shortcutBusy
      onClicked: setup.shortcutApply(shortcutField.text)
    }
  }

  Text {
    width: parent.width
    text: "Super, Ctrl, Alt, Shift + a key. Leave empty to disable."
    color: setup.foreground
    opacity: 0.5
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    visible: setup.shortcutMessage !== ""
    width: parent.width
    text: setup.shortcutMessage
    textFormat: Text.PlainText
    color: setup.shortcutOk ? setup.foreground : setup.errorColor
    opacity: setup.shortcutOk ? 0.7 : 1
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // ---- channels -------------------------------------------------------------

  Item {
    visible: setup.signedIn
    width: parent.width
    height: visible ? Style.space(40) : 0

    Column {
      anchors.left: parent.left
      anchors.right: refreshChannelsButton.left
      anchors.rightMargin: setup.contentSpacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Text {
        text: "Channels"
        color: setup.foreground
        font.family: setup.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        text: setup.channelCacheText
        textFormat: Text.PlainText
        color: setup.foreground
        opacity: 0.5
        font.family: setup.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Button {
      id: refreshChannelsButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(32)
      text: setup.channelRefreshBusy ? "Refreshing…" : "Refresh channels"
      enabled: !setup.channelRefreshBusy && !setup.busy
      onClicked: setup.channelRefreshRequested()
    }
  }

  // ---- API key --------------------------------------------------------------

  Text {
    visible: !setup.cliMissing
    text: "API key"
    color: setup.foreground
    font.family: setup.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Text {
    visible: !setup.cliMissing
    width: parent.width
    text: "Create one at publish.buffer.com → Settings → API. Stored in ~/.config/omarchy-buffer with 0600 permissions and passed to the Buffer CLI through its environment, never on the command line."
    color: setup.foreground
    opacity: 0.5
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  TextField {
    id: keyField
    visible: !setup.cliMissing
    width: parent.width
    enabled: !setup.busy
    password: true
    placeholderText: "Buffer API key"
    color: setup.foreground
    font.family: setup.fontFamily
    Keys.onReturnPressed: saveButton.clicked()
    Keys.onEnterPressed: saveButton.clicked()
    Keys.onEscapePressed: function(event) { setup.dismissRequested(); event.accepted = true }
  }

  // ---- missing CLI -----------------------------------------------------------

  Text {
    visible: setup.cliMissing
    width: parent.width
    text: "The Buffer CLI is not installed. Run:\n\nnpm install -g @bufferapp/cli\n\n(Node 18 or later.)"
    textFormat: Text.PlainText
    color: setup.errorColor
    font.family: setup.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Text {
    visible: setup.statusText !== ""
    width: parent.width
    text: setup.statusText
    textFormat: Text.PlainText
    color: setup.statusError ? setup.errorColor : setup.foreground
    opacity: setup.statusError ? 1 : 0.62
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item {
    width: parent.width
    height: Style.space(32)

    Button {
      id: backButton
      anchors.left: parent.left
      height: parent.height
      visible: setup.canGoBack
      text: "Back"
      enabled: !setup.busy
      onClicked: setup.backRequested()
    }

    Row {
      anchors.right: parent.right
      spacing: setup.contentSpacing
      height: parent.height

      Button {
        id: clearButton
        height: parent.height
        enabled: !setup.busy
        visible: setup.statusText !== "" && setup.statusError
        text: "Clear"
        onClicked: {
          keyField.text = ""
          setup.clearStatus()
          keyField.forceActiveFocus()
        }
      }

      Button {
        id: saveButton
        height: parent.height
        visible: !setup.cliMissing
        text: setup.busy ? "Verifying…" : "Save & verify"
        selected: true
        enabled: !setup.busy && keyField.text.trim() !== ""
        onClicked: {
          if (setup.busy) return
          setup.saved(keyField.text.trim())
        }
      }
    }
  }
}
