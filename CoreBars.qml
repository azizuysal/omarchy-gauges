import QtQuick
import qs.Commons

// One upright bar per processor core.
Item {
  id: root

  property var ctx: null
  property var cores: []

  readonly property real gap: cores.length > 32 ? 1 : Style.space(3)
  readonly property real barWidth: cores.length > 0 ? Math.max(1, (width - gap * (cores.length - 1)) / cores.length) : 0

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: Style.space(34)

  Repeater {
    model: root.cores.length

    Item {
      id: slot
      required property int index
      readonly property real level: Math.max(0, Math.min(1, Number(root.cores[index]) || 0))

      x: index * (root.barWidth + root.gap)
      width: root.barWidth
      height: root.height

      Rectangle {
        anchors.fill: parent
        radius: Math.min(2, width / 2)
        color: root.ctx ? root.ctx.faint : "transparent"
      }

      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        radius: Math.min(2, width / 2)
        height: Math.max(slot.level > 0 ? 1 : 0, parent.height * slot.level)
        color: root.ctx ? root.ctx.levelColor(slot.level, 0.9, 2) : "transparent"

        Behavior on height { NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic } }
      }
    }
  }
}
