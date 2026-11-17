import QtQuick
import qs.Commons

// The small picture a bar item shows in place of a number:
//
//   "history"  the last few readings as a bar graph (processor, graphics)
//   "column"   an upright gauge filling from the bottom, with an optional
//              fainter second part above it (memory in use, then cache)
//   "level"    a capacity bar filling from the side (disk space)
//
// Sized from the bar's icon height so it follows the bar's scale.
Canvas {
  id: root

  property string kind: "history"
  property color color: "white"
  // "history": readings from 0 to 1, oldest first.
  property var values: []
  // "column" and "level": the solid part, and for the column a fainter part
  // after it.
  property real fraction: 0
  property real extra: 0

  readonly property int bars: 10
  readonly property real unit: Style.bar.iconSize / 12
  readonly property real barWidth: 2 * unit
  readonly property real barGap: unit

  implicitHeight: Style.bar.iconSize
  implicitWidth: kind === "history" ? bars * barWidth + (bars - 1) * barGap
    : kind === "level" ? 20 * unit
    : 7 * unit
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

  function paintColumn(context) {
    var used = clamp(fraction) * height
    var more = Math.min(1 - clamp(fraction), clamp(extra)) * height
    slab(context, 0, 0, width, height)
    context.fillStyle = tint(0.18)
    context.fill()
    // Clipped to the outline so the fill keeps the rounded corners.
    context.save()
    slab(context, 0, 0, width, height)
    context.clip()
    if (more > 0) {
      context.fillStyle = tint(0.4)
      context.fillRect(0, height - used - more, width, more)
    }
    if (used > 0) {
      context.fillStyle = tint(1)
      context.fillRect(0, height - Math.max(unit, used), width, Math.max(unit, used))
    }
    context.restore()
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
    else if (kind === "column") paintColumn(context)
    else paintLevel(context)
  }
}
