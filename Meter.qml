import QtQuick
import qs.Commons

// A horizontal level bar. `fraction` is the solid part; `extra` is a second,
// fainter part drawn after it (memory's reclaimable cache, say).
Item {
  id: root

  property var ctx: null
  property real fraction: 0
  property real extra: 0
  property color fillColor: ctx ? ctx.foreground : "transparent"

  readonly property real clamped: Math.max(0, Math.min(1, fraction))
  readonly property real clampedExtra: Math.max(0, Math.min(1 - clamped, extra))

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: Style.space(6)

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: root.ctx ? root.ctx.faint : "transparent"
  }

  Rectangle {
    visible: root.clampedExtra > 0
    anchors.verticalCenter: track.verticalCenter
    x: LayoutMirroring.enabled ? track.width - width : 0
    height: track.height
    radius: track.radius
    width: Math.max(track.height, track.width * (root.clamped + root.clampedExtra))
    color: root.fillColor
    opacity: 0.3

    Behavior on width { NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic } }
  }

  Rectangle {
    visible: root.clamped > 0
    anchors.verticalCenter: track.verticalCenter
    x: LayoutMirroring.enabled ? track.width - width : 0
    height: track.height
    radius: track.radius
    width: Math.max(track.height, track.width * root.clamped)
    color: root.fillColor

    Behavior on width { NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: Style.duration(200) } }
  }
}
