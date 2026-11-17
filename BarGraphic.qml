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
  // How many readings the "mirror" graph draws across its width.
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

  // Traces one history as a smooth curve, `direction` -1 for above the
  // middle line and 1 for below, and returns where it started. The curve runs
  // through the midpoints between readings, which rounds every corner.
  function mirrorCurve(context, series, middle, reach, direction) {
    var count = Math.min(mirrorSamples, series.length)
    var step = width / (mirrorSamples - 1)
    var first = series.length - count
    function px(i) { return width - (count - 1 - i) * step }
    function py(i) { return middle + direction * clamp(series[first + i]) * reach }
    context.moveTo(px(0), py(0))
    for (var i = 1; i < count - 1; i++) {
      context.quadraticCurveTo(px(i), py(i), (px(i) + px(i + 1)) / 2, (py(i) + py(i + 1)) / 2)
    }
    context.lineTo(px(count - 1), py(count - 1))
    return px(0)
  }

  // Two smooth lines either side of a faint middle line, each with a light
  // wash between it and the middle.
  function paintMirror(context) {
    var middle = height / 2
    var reach = middle - unit
    context.fillStyle = tint(0.25)
    context.fillRect(0, middle - unit / 4, width, unit / 2)

    var halves = [{ series: values, direction: -1 }, { series: secondary, direction: 1 }]
    for (var h = 0; h < halves.length; h++) {
      var series = halves[h].series
      if (series.length < 2) continue
      context.beginPath()
      var start = mirrorCurve(context, series, middle, reach, halves[h].direction)
      context.lineTo(width, middle)
      context.lineTo(start, middle)
      context.closePath()
      context.fillStyle = tint(0.22)
      context.fill()

      context.beginPath()
      mirrorCurve(context, series, middle, reach, halves[h].direction)
      context.lineWidth = unit
      context.lineJoin = "round"
      context.lineCap = "round"
      context.strokeStyle = tint(1)
      context.stroke()
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
