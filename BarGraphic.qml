import QtQuick
import qs.Commons

// The small picture a bar item shows in place of a number:
//
//   "history"  the last few readings as a bar graph (processor, graphics)
//   "mirror"   two histories about a middle line: `values` rising above
//              it, `secondary` hanging below (network up and down)
//   "column"   an upright gauge filling from the bottom, with an optional
//              fainter second part above it (memory in use, then cache)
//   "pie"      how much of a whole is taken (disk space)
//
// Sized from the bar's icon height so it follows the bar's scale.
Canvas {
  id: root

  property string kind: "history"
  property color color: "white"
  // "history": readings from 0 to 1, oldest first.
  property var values: []
  // "mirror": the readings drawn below the line.
  property var secondary: []
  // "column" and "pie": the solid part, and for the column a fainter part
  // after it.
  property real fraction: 0
  property real extra: 0

  readonly property int bars: 10
  // How many readings the "mirror" graph draws, one unit wide each.
  readonly property int mirrorSamples: 29
  readonly property real unit: Style.bar.iconSize / 12
  readonly property real barWidth: 2 * unit
  readonly property real barGap: unit

  implicitHeight: Style.bar.iconSize
  implicitWidth: kind === "history" || kind === "mirror" ? bars * barWidth + (bars - 1) * barGap
    : kind === "column" ? 7 * unit
    : implicitHeight
  width: implicitWidth
  height: implicitHeight

  onKindChanged: requestPaint()
  onColorChanged: requestPaint()
  onValuesChanged: requestPaint()
  onSecondaryChanged: requestPaint()
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

  // One thin line per reading, touching its neighbours, so the two
  // histories read as silhouettes either side of the middle line.
  function paintMirror(context) {
    var middle = Math.round(height / 2)
    var half = middle - unit / 2
    context.fillStyle = tint(0.3)
    context.fillRect(0, middle - unit / 2, width, unit)
    context.fillStyle = tint(1)
    for (var slot = 0; slot < mirrorSamples; slot++) {
      var x = slot * unit
      var above = values.length - mirrorSamples + slot
      var below = secondary.length - mirrorSamples + slot
      // A trickle too small to draw is left off, so an idle network is a
      // clean line rather than a thick one.
      var up = above >= 0 ? clamp(values[above]) * half : 0
      if (up >= unit / 2) {
        context.fillRect(x, middle - unit / 2 - up, unit, up)
      }
      var down = below >= 0 ? clamp(secondary[below]) * half : 0
      if (down >= unit / 2) {
        context.fillRect(x, middle + unit / 2, unit, down)
      }
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

  function paintPie(context) {
    var cx = width / 2
    var cy = height / 2
    var radius = Math.min(width, height) / 2
    var top = -Math.PI / 2
    var used = clamp(fraction)

    context.beginPath()
    context.arc(cx, cy, radius, 0, Math.PI * 2)
    context.fillStyle = tint(0.18)
    context.fill()
    if (used <= 0) return

    context.beginPath()
    context.moveTo(cx, cy)
    context.arc(cx, cy, radius, top, top + used * Math.PI * 2)
    context.closePath()
    context.fillStyle = tint(1)
    context.fill()
  }

  onPaint: {
    var context = getContext("2d")
    context.reset()
    if (kind === "history") paintHistory(context)
    else if (kind === "mirror") paintMirror(context)
    else if (kind === "column") paintColumn(context)
    else paintPie(context)
  }
}
