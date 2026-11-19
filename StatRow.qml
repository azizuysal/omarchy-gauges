import QtQuick
import qs.Commons

// A label on the leading edge and its reading on the trailing one.
Item {
  id: root

  property var ctx: null
  property string label: ""
  property string value: ""
  property color valueColor: ctx ? ctx.foreground : "transparent"
  // Drawn just before the reading, a little larger: a flag, which fonts
  // draw smaller than the digits beside it.
  property string prefix: ""

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

  Label {
    id: labelText
    ctx: root.ctx
    dim: true
    text: root.label
    anchors.left: parent.left
    anchors.right: prefixText.visible ? prefixText.left : valueText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
  }

  Label {
    id: prefixText
    visible: root.prefix !== "" && root.value !== ""
    ctx: root.ctx
    text: root.prefix
    font.pixelSize: Math.round(Style.font.bodySmall * 1.4)
    elide: Text.ElideNone
    anchors.right: valueText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
  }

  Label {
    id: valueText
    ctx: root.ctx
    text: root.value !== "" ? root.value : "—"
    color: root.valueColor
    elide: Text.ElideNone
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
  }
}
