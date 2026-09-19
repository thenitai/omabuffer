import QtQuick
import qs.Ui

// Bar icon: opens the Buffer composer overlay. A discoverable fallback for
// when the global shortcut is disabled or unavailable.

BarWidget {
  id: root
  moduleName: "thenitai.omabuffer"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uEF96"
    tooltipText: "Buffer composer"
    onPressed: function(mouseButton) {
      if (mouseButton !== Qt.LeftButton || !root.bar || !root.bar.shell) return
      root.bar.shell.toggle("thenitai.omabuffer", "{}")
    }
  }
}
