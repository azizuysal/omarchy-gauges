import QtQuick
import qs.Commons

// The top of every panel: icon, title over a small caption, and the headline
// reading on the trailing edge, as Omarchy's own power panel lays it out.
Item {
  id: root

  property var ctx: null
  property string icon: ""
  property string title: ""
  property string caption: ""
  property string value: ""
  property color valueColor: ctx ? ctx.foreground : "transparent"

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(iconText.implicitHeight, labels.implicitHeight, valueText.implicitHeight)

  Text {
    id: iconText
    textFormat: Text.PlainText
    text: root.icon
    color: root.ctx ? root.ctx.foreground : "transparent"
    font.family: root.ctx ? root.ctx.fontFamily : Style.font.family
    font.pixelSize: Style.font.display
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
  }

  Column {
    id: labels
    anchors.left: iconText.right
    anchors.leftMargin: Style.space(14)
    anchors.right: valueText.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: root.title
      width: parent.width
      color: root.ctx ? root.ctx.foreground : "transparent"
      font.family: root.ctx ? root.ctx.fontFamily : Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      text: root.caption.toUpperCase()
      visible: text !== ""
      width: parent.width
      color: root.ctx ? root.ctx.dim : "transparent"
      font.family: root.ctx ? root.ctx.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      elide: Text.ElideRight
    }
  }

  Text {
    id: valueText
    textFormat: Text.PlainText
    text: root.value !== "" ? root.value : "—"
    color: root.valueColor
    font.family: root.ctx ? root.ctx.fontFamily : Style.font.family
    font.pixelSize: Style.font.displayLarge
    font.bold: true
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter

    Behavior on color { ColorAnimation { duration: Style.duration(200) } }
  }
}
