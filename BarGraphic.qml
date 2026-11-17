import QtQuick
import qs.Commons

// The small picture a bar item shows in place of a number:
//
//   "history"  the last few readings as a bar graph (processor, graphics)
//   "pie"      how much of a whole is taken, with an optional fainter second
//              slice after it (memory in use, then cache)
//   "level"    a capacity bar (disk space)
//
// Sized from the bar's icon height so it follows the bar's scale.
Canvas {
  id: root

  property string kind: "history"
  property color color: "white"
  // "history": readings from 0 to 1, oldest first.
  property var values: []
  // "pie" and "level": the solid part, and for the pie a fainter part after it.
  property real fraction: 0
  property real extra: 0

  readonly property int bars: 10
  readonly property real unit: Style.bar.iconSize / 12
  readonly property real barWidth: 2 * unit
  readonly property real barGap: unit

  implicitHeight: Style.bar.iconSize
  implicitWidth: kind === "history" ? bars * barWidth + (bars - 1) * barGap
    : kind === "level" ? 20 * unit
    : implicitHeight
  width: implicitWidth
  height: implicitHeight

  onKindChanged: requestPaint()
  onColorChanged: requestPaint()
  onValuesChanged: requestPaint()
  onFractionChanged: requestPaint()
  onExtraChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function clamp(value) {
    return Math.max(0, Math.min(1, Number(value) || 0))
  }

  function tint(alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function paintHistory(context) {
    var count = Math.min(bars, values.length)
    for (var slot = 0; slot < bars; slot++) {
      var x = slot * (barWidth + barGap)
      context.fillStyle = tint(0.18)
      context.fillRect(x, 0, barWidth, height)
      // The newest reading takes the last slot; a short history leaves the
      // leading slots empty.
      var index = values.length - bars + slot
      if (index < 0 || count === 0) continue
      var tall = Math.max(unit, clamp(values[index]) * height)
      context.fillStyle = tint(1)
      context.fillRect(x, height - tall, barWidth, tall)
    }
  }

  function paintPie(context) {
    var cx = width / 2
    var cy = height / 2
    var radius = Math.min(width, height) / 2
    var top = -Math.PI / 2
    var used = clamp(fraction)
    var more = Math.min(1 - used, clamp(extra))

    context.beginPath()
    context.arc(cx, cy, radius, 0, Math.PI * 2)
    context.fillStyle = tint(0.18)
    context.fill()

    if (more > 0) {
      context.beginPath()
      context.moveTo(cx, cy)
      context.arc(cx, cy, radius, top + used * Math.PI * 2, top + (used + more) * Math.PI * 2)
      context.closePath()
      context.fillStyle = tint(0.4)
      context.fill()
    }

    if (used > 0) {
      context.beginPath()
      context.moveTo(cx, cy)
      context.arc(cx, cy, radius, top, top + used * Math.PI * 2)
      context.closePath()
      context.fillStyle = tint(1)
      context.fill()
    }
  }

  // Corners only slightly rounded: with fully round ends a nearly empty bar
  // reads as a toggle switch.
  function slab(context, x, y, w, h) {
    var r = Math.min(1.5 * unit, w / 2, h / 2)
    context.beginPath()
    context.moveTo(x + r, y)
    context.arcTo(x + w, y, x + w, y + h, r)
    context.arcTo(x + w, y + h, x, y + h, r)
    context.arcTo(x, y + h, x, y, r)
    context.arcTo(x, y, x + w, y, r)
    context.closePath()
  }

  function paintLevel(context) {
    var tall = 8 * unit
    var y = (height - tall) / 2
    slab(context, 0, y, width, tall)
    context.fillStyle = tint(0.18)
    context.fill()
    var filled = clamp(fraction) * width
    if (filled <= 0) return
    // Never a sliver too thin to see.
    slab(context, 0, y, Math.max(2 * unit, filled), tall)
    context.fillStyle = tint(1)
    context.fill()
  }

  onPaint: {
    var context = getContext("2d")
    context.reset()
    if (kind === "history") paintHistory(context)
    else if (kind === "pie") paintPie(context)
    else paintLevel(context)
  }
}
