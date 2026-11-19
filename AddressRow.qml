import QtQuick
import qs.Commons

// A label and an address. Clicking the row copies the address.
Item {
  id: root

  property var ctx: null
  property string label: ""
  // What is shown and copied.
  property string address: ""
  // Drawn before the address but not copied: a flag.
  property string prefix: ""
  // Shown in place of an address there is not, or not yet.
  property string placeholder: ""
  property bool copied: false

  width: parent ? parent.width : implicitWidth
  implicitHeight: row.implicitHeight

  StatRow {
    id: row
    ctx: root.ctx
    label: root.label
    value: root.copied ? root.ctx.strings.t("network.copied")
      : root.address === "" ? root.placeholder : root.address
    prefix: root.copied || root.address === "" ? "" : root.prefix
    opacity: area.containsMouse && root.address !== "" ? 0.7 : 1
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.address !== ""
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.ctx.copyText(root.address)
      root.copied = true
      reset.restart()
    }
  }

  Timer {
    id: reset
    interval: 1200
    onTriggered: root.copied = false
  }
}
