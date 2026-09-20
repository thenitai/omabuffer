import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "BufferApi.js" as Buffer

// The post composer: text area, multi-select channel chips, queue/now
// toggle, link card, character counter and the send action.

Column {
  id: c

  spacing: c.contentSpacing

  property var channelsModel: null
  property var channelIds: []
  property string mode: Buffer.MODE_QUEUE
  property string linkCardUrl: ""
  property bool sending: false
  property bool checking: false

  property color foreground: Color.menu.text
  property color errorColor: Color.urgent
  property string fontFamily: Style.font.menuFamily
  property int contentSpacing: Style.space(14)
  readonly property int footerHeight: Style.space(32)

  signal postRequested()
  signal dismissRequested()
  signal settingsRequested()
  signal channelToggled(string id)
  signal modePicked(string mode)
  signal linkCardRequested()
  signal clearLinkCardRequested()

  component FooterLink: Text {
    id: footerLink

    signal activated()

    y: (parent.height - height) / 2
    color: c.foreground
    opacity: footerLinkMouse.containsMouse ? 1 : 0.55
    font.family: c.fontFamily
    font.pixelSize: Style.font.caption

    MouseArea {
      id: footerLinkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: footerLink.activated()
    }
  }

  readonly property alias text: textArea.text
  readonly property alias textAreaItem: textArea

  // Services of the selected channels — drives the counter and link card.
  readonly property var selectedServices: {
    var out = []
    if (c.channelsModel) {
      for (var i = 0; i < c.channelsModel.count; i++) {
        var ch = c.channelsModel.get(i)
        if (c.channelIds.indexOf(ch.id) !== -1) out.push(String(ch.service || ""))
      }
    }
    return out
  }
  readonly property int remaining: Buffer.minRemaining(textArea.text, c.selectedServices)
  readonly property bool overLimit: c.selectedServices.length > 0 && c.remaining < 0
  readonly property string cardUrl: Buffer.firstUrl(textArea.text)
  readonly property bool linkCardAvailable: c.cardUrl !== "" && c.linkCardUrl === ""
    && c.anyLinkCardService
  readonly property bool anyLinkCardService: {
    for (var i = 0; i < c.selectedServices.length; i++)
      if (Buffer.supportsLinkCard(c.selectedServices[i])) return true
    return false
  }
  readonly property bool canPost: !c.sending && !c.checking && c.channelIds.length > 0
    && !c.overLimit && textArea.text.trim() !== ""

  function insertClipboardText(t) {
    if (!t) return
    textArea.insert(textArea.cursorPosition, t)
    textArea.forceActiveFocus()
  }

  function clearDraft() {
    textArea.clear()
  }

  TextArea {
    id: textArea
    width: parent.width
    height: Style.space(120)
    enabled: !c.sending
    wrapMode: TextEdit.Wrap
    clip: true
    placeholderText: "What's up?"
    placeholderTextColor: Qt.darker(c.foreground, 1.6)
    color: c.foreground
    selectionColor: Style.selectionFillFor(c.foreground, Color.accent)
    selectedTextColor: c.foreground
    font.family: c.fontFamily
    font.pixelSize: Style.font.body

    background: BorderSurface {
      color: Style.controlFill(textArea.activeFocus, textArea.hovered, c.foreground, Color.accent)
      borderSpec: Border.controlSpec(textArea.activeFocus ? "focus" : (textArea.hovered ? "hover-cursor" : "normal"), c.foreground, Color.accent)
      radius: Style.cornerRadius
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        c.dismissRequested()
        event.accepted = true
      } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                 && (event.modifiers & Qt.ControlModifier)) {
        c.postRequested()
        event.accepted = true
      } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
        textArea.paste()
        event.accepted = true
      } else if ((event.modifiers & Qt.MetaModifier)
                 && !(event.modifiers & Qt.ControlModifier)) {
        // Super-mapped editing keys (delivered when the triggering Hyprland
        // bind is created with allow_input_capture = true).
        if (event.key === Qt.Key_A) {
          textArea.selectAll()
          event.accepted = true
        } else if (event.key === Qt.Key_V) {
          textArea.paste()
          event.accepted = true
        } else if (event.key === Qt.Key_C) {
          textArea.copy()
          event.accepted = true
        } else if (event.key === Qt.Key_X) {
          textArea.cut()
          event.accepted = true
        } else if (event.key === Qt.Key_Z) {
          textArea.undo()
          event.accepted = true
        }
      }
    }
  }

  // ---- channel chips (multi-select) -------------------------------------------

  Flow {
    width: parent.width
    visible: c.channelsModel && c.channelsModel.count > 0
    spacing: Style.space(6)

    Repeater {
      model: c.channelsModel

      Button {
        required property string id
        required property string name
        required property string displayName
        required property string service

        height: c.footerHeight
        text: (displayName !== "" ? displayName : name) + " · " + service
        selected: c.channelIds.indexOf(id) !== -1
        enabled: !c.sending
        tooltipText: c.channelIds.indexOf(id) !== -1
          ? "Selected — click to remove"
          : "Add " + (displayName !== "" ? displayName : name) + " (" + service + ") to this post"
        onClicked: c.channelToggled(id)
      }
    }
  }

  // ---- queue / now toggle --------------------------------------------------------

  Row {
    spacing: Style.space(6)

    Button {
      height: c.footerHeight
      text: "Queue"
      selected: c.mode === Buffer.MODE_QUEUE
      enabled: !c.sending
      tooltipText: "Add to the channel's Buffer queue"
      onClicked: c.modePicked(Buffer.MODE_QUEUE)
    }

    Button {
      height: c.footerHeight
      text: "Now"
      selected: c.mode === Buffer.MODE_NOW
      enabled: !c.sending
      tooltipText: "Publish immediately"
      onClicked: c.modePicked(Buffer.MODE_NOW)
    }
  }

  // ---- link card ------------------------------------------------------------------

  Button {
    visible: c.linkCardAvailable
    height: c.footerHeight
    text: "Link card"
    enabled: !c.sending
    tooltipText: "Attach a link card for the pasted URL — Buffer fetches the page, including its image"
    onClicked: c.linkCardRequested()
  }

  Button {
    visible: c.linkCardUrl !== ""
    selected: true
    height: c.footerHeight
    text: "Card: " + Buffer.hostOf(c.linkCardUrl)
    enabled: !c.sending
    onClicked: c.clearLinkCardRequested()
  }

  // ---- footer actions ----------------------------------------------------------------

  Item {
    width: parent.width
    height: c.footerHeight

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      FooterLink {
        text: "Settings"
        onActivated: c.settingsRequested()
      }

      FooterLink {
        text: "Go to Buffer"
        onActivated: Qt.openUrlExternally("https://publish.buffer.com")
      }
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)

      Text {
        y: (parent.height - height) / 2
        visible: c.channelIds.length > 0
        text: c.overLimit ? (c.remaining + " over") : (c.remaining + " left")
        color: c.overLimit ? c.errorColor : c.foreground
        opacity: c.overLimit ? 1 : 0.55
        font.family: c.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        id: postButton
        height: c.footerHeight
        text: c.checking ? "Checking…" : (c.sending ? "Sending…" : (c.mode === Buffer.MODE_NOW ? "Post now" : "Queue"))
        selected: true
        enabled: c.canPost
        onClicked: c.postRequested()
      }
    }
  }
}
