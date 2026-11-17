import QtQuick
import qs.Commons

// A small history graph. The newest reading sits at the trailing edge and
// older ones scroll away from it, so a short history starts from that edge
// rather than stretching to fill.
Canvas {
  id: root

  property var ctx: null
  property var values: []
  // An optional second line, drawn unfilled and fainter.
  property var secondary: []
  // The value at the top of the graph. Zero scales to the tallest reading,
  // but never below `floor`, so a quiet disk does not look frantic.
  property real ceiling: 1
  property real floor: 0
  property int capacity: 60
  property color lineColor: ctx ? ctx.foreground : "transparent"

  readonly property real peak: {
    if (ceiling > 0) return ceiling
    var top = floor
    for (var i = 0; i < values.length; i++) if (values[i] > top) top = values[i]
    for (var j = 0; j < secondary.length; j++) if (secondary[j] > top) top = secondary[j]
    return top > 0 ? top : 1
  }

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: Style.space(44)

  onValuesChanged: requestPaint()
  onSecondaryChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onPeakChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function trace(context, series, inset) {
    var count = series.length
    var step = width / Math.max(1, capacity - 1)
    var usable = height - inset * 2
    context.beginPath()
    for (var i = 0; i < count; i++) {
      var x = width - (count - 1 - i) * step
      var y = inset + usable * (1 - Math.max(0, Math.min(1, series[i] / peak)))
      if (i === 0) context.moveTo(x, y)
      else context.lineTo(x, y)
    }
    return width - (count - 1) * step
  }

  onPaint: {
    var context = getContext("2d")
    context.reset()
    var inset = 1
    var c = lineColor

    // Baseline.
    context.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.12)
    context.fillRect(0, height - 1, width, 1)

    if (values.length > 1) {
      var startX = trace(context, values, inset)
      context.lineTo(width, height)
      context.lineTo(startX, height)
      context.closePath()
      context.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.14)
      context.fill()

      trace(context, values, inset)
      context.lineWidth = 1.5
      context.lineJoin = "round"
      context.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.9)
      context.stroke()
    }

    if (secondary.length > 1) {
      trace(context, secondary, inset)
      context.lineWidth = 1.5
      context.lineJoin = "round"
      context.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.4)
      context.stroke()
    }
  }
}
