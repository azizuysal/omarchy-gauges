import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The bar item: a small graph per metric (or its icon, with or without the
// percentage), each opening the same popup on its own detail view. Readings come from Service.qml, which the
// shell runs once however many bars (monitors) show this widget.
Panel {
  id: root

  ipcTarget: "sysmon"
  // The base's handler only opens and closes; ours also takes a reading to
  // open on, e.g. `omarchy-shell sysmon show memory`, handy for keybindings.
  manageIpc: false

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function show(item: string): string {
      if (root.items.indexOf(item) === -1) return "unknown reading: " + item
      root.active = item
      root.open()
      return "ok"
    }
  }

  readonly property string pluginId: "azizuysal.sysmon"
  readonly property var allItems: ["cpu", "memory", "gpu", "disk", "network"]

  // ---- readings
  readonly property var sharedStats: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(pluginId) : null
  // If the shell hands us no service (an older Omarchy, say), sample here.
  property bool localStatsAllowed: false
  readonly property var stats: sharedStats || localStats.item

  Timer {
    interval: 1500
    running: root.sharedStats === null
    onTriggered: root.localStatsAllowed = true
  }

  Loader {
    id: localStats
    active: root.localStatsAllowed && root.sharedStats === null
    source: Qt.resolvedUrl("Service.qml")
  }

  // ---- settings
  readonly property bool vertical: bar ? bar.vertical : false
  // How each reading is shown: "graph", "gauge", "pie", "percentage", "icon",
  // "icon and percentage" or "off". A string per reading rather than one map,
  // so the bindings below only re-run when a setting actually changes.
  // The network has rates, not a level, so its styles are "graph", "rates",
  // "icon" and "off".
  readonly property var defaultStyles: ({ cpu: "graph", memory: "gauge", gpu: "graph", disk: "pie", network: "graph" })
  readonly property var knownStyles: ["graph", "gauge", "pie", "percentage", "icon", "icon and percentage", "off"]
  readonly property var networkStyles: ["graph", "rates", "icon", "off"]
  function styleSetting(item) {
    var chosen = String(setting(item, defaultStyles[item])).toLowerCase()
    var known = item === "network" ? networkStyles : knownStyles
    if (known.indexOf(chosen) === -1) chosen = defaultStyles[item]
    // A vertical bar is too narrow for anything but the icon.
    return vertical && chosen !== "off" ? "icon" : chosen
  }
  readonly property string cpuStyle: styleSetting("cpu")
  readonly property string memoryStyle: styleSetting("memory")
  readonly property string gpuStyle: styleSetting("gpu")
  readonly property string diskStyle: styleSetting("disk")
  readonly property string networkStyle: styleSetting("network")
  function style(item) {
    return item === "cpu" ? cpuStyle : item === "memory" ? memoryStyle : item === "gpu" ? gpuStyle
      : item === "disk" ? diskStyle : networkStyle
  }
  function drawn(item) {
    var chosen = style(item)
    return chosen === "graph" || chosen === "gauge" || chosen === "pie"
  }

  // The percentage beside a graph, gauge or pie.
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // Memory and disk turn the warning colour from this share upward.
  readonly property real warnAt: {
    var percent = Number(setting("warnAt", 90))
    return isFinite(percent) ? Math.max(1, Math.min(100, percent)) / 100 : 0.9
  }

  // No GPU item on a machine whose graphics report no load. A property of
  // its own so `items` only changes when that does, not on every sample: a
  // new list rebuilds every bar button.
  readonly property bool hasGpu: stats ? stats.gpuAvailable : false
  readonly property var items: {
    var styles = { cpu: cpuStyle, memory: memoryStyle, gpu: gpuStyle, disk: diskStyle, network: networkStyle }
    return allItems.filter(function(item) {
      return styles[item] !== "off" && (item !== "gpu" || hasGpu)
    })
  }

  // ---- which detail view the popup shows
  property string active: "cpu"
  readonly property int activeIndex: Math.max(0, items.indexOf(active))

  function show(item) {
    if (items.indexOf(item) === -1) return
    if (opened && active === item) { close(); return }
    active = item
    open()
  }

  function cycle(direction) {
    if (items.length === 0) return
    active = items[(activeIndex + direction + items.length) % items.length]
  }

  onItemsChanged: if (items.indexOf(active) === -1 && items.length > 0) active = items[0]
  onOpenedChanged: if (opened) {
    if (items.indexOf(active) === -1 && items.length > 0) active = items[0]
    if (stats) stats.refreshFilesystems()
  }

  // Drive temperature is read when the disk view opens and then slowly while
  // it stays open; see Service.refreshDiskTemps for why it is not polled.
  readonly property bool wantsDiskTemps: opened && active === "disk"
  onWantsDiskTempsChanged: if (wantsDiskTemps && stats) stats.refreshDiskTemps()
  Timer {
    interval: 30000
    running: root.wantsDiskTemps
    repeat: true
    onTriggered: if (root.stats) root.stats.refreshDiskTemps()
  }

  // The process list costs a `top` run every few seconds, so ask for it only
  // while a view that shows it is open.
  readonly property bool wantsProcesses: opened && (active === "cpu" || active === "memory")
  property bool watching: false
  function syncWatch() {
    if (!stats || wantsProcesses === watching) return
    stats.watchProcesses(wantsProcesses)
    watching = wantsProcesses
  }
  onWantsProcessesChanged: syncWatch()

  // Likewise the list of programs using the network.
  readonly property bool wantsNetPrograms: opened && active === "network"
  property bool watchingNet: false
  function syncNetWatch() {
    if (!stats || wantsNetPrograms === watchingNet) return
    stats.watchNetPrograms(wantsNetPrograms)
    watchingNet = wantsNetPrograms
  }
  onWantsNetProgramsChanged: syncNetWatch()

  onStatsChanged: { watching = false; watchingNet = false; syncWatch(); syncNetWatch() }
  Component.onDestruction: {
    if (watching && stats) stats.watchProcesses(false)
    if (watchingNet && stats) stats.watchNetPrograms(false)
  }

  // ---- shared look, read by the views as `ctx`
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property alias strings: translations
  readonly property var icons: ({
    cpu: String.fromCodePoint(0xF4BC),
    memory: String.fromCodePoint(0xF061A),
    gpu: String.fromCodePoint(0xF08AE),
    disk: String.fromCodePoint(0xF02CA),
    network: String.fromCodePoint(0xF04E1)
  })

  Commons.Translations {
    id: translations
    directory: Qt.resolvedUrl("i18n")
  }

  function levelColor(fraction, critical) {
    return fraction >= critical ? urgent : foreground
  }

  function percentText(fraction, decimals) {
    var value = decimals > 0
      ? Commons.I18n.formatNumber(Math.max(0, fraction) * 100, decimals)
      : Commons.I18n.formatNumber(Model.percent(fraction))
    return value + "%"
  }

  function bytesText(bytes) {
    var parts = Model.bytesParts(bytes)
    return Commons.I18n.formatNumber(parts.value, parts.decimals) + " " + parts.unit
  }

  function rateText(bytesPerSecond) {
    return translations.t("common.perSecond").arg(bytesText(bytesPerSecond))
  }

  function tempText(celsius) {
    if (celsius === null || celsius === undefined) return ""
    return Commons.I18n.formatNumber(Math.round(celsius)) + "°C"
  }

  function uptimeText(seconds) {
    var parts = Model.durationParts(seconds)
    if (parts.days > 0) return translations.t("cpu.uptimeDays").arg(parts.days).arg(parts.hours)
    if (parts.hours > 0) return translations.t("cpu.uptimeHours").arg(parts.hours).arg(parts.minutes)
    return translations.t("cpu.uptimeMinutes").arg(parts.minutes)
  }

  // ---- the bar
  // The fraction a bar item shows, or -1 when it has nothing to show.
  function reading(item) {
    if (!stats) return -1
    if (item === "cpu") return stats.ready ? stats.cpuUsage : -1
    if (item === "memory") return stats.memory.total > 0 ? stats.memory.fraction : -1
    if (item === "gpu") return stats.gpu ? stats.gpu.busy : -1
    if (item === "disk") return stats.filesystem ? stats.filesystem.fraction : -1
    // The network has no level; it is either measured or not.
    if (item === "network") return stats.netReady ? 0 : -1
    return -1
  }

  function barLabel(item) {
    var value = reading(item)
    if (value < 0) return ""
    // Padded to three characters so the icon does not shift between 9% and 10%.
    return ("  " + Model.percent(value) + "%").slice(-Math.max(3, String(Model.percent(value)).length + 1))
  }

  // A full disk or exhausted memory is worth a warning colour in the bar; a
  // busy processor or graphics card is just the machine doing its job.
  function alarming(item) {
    return (item === "memory" || item === "disk") && reading(item) >= warnAt
  }

  // What a drawn item shows; see BarGraphic.
  function graphicKind(item) {
    if (item === "network") return "mirror"
    var chosen = style(item)
    return chosen === "gauge" ? "column" : chosen === "pie" ? "pie" : "history"
  }

  // As many readings as BarGraphic's "mirror" graph draws.
  readonly property int networkSamples: 12
  // The busiest moment in the network graph's readings, up or down, and
  // never less than a floor, so a trickle of background traffic stays small.
  readonly property real networkGraphFloor: 128 * 1024
  readonly property real networkGraphPeak: {
    var peak = networkGraphFloor
    if (!stats) return peak
    var series = [stats.netDownHistory.slice(-networkSamples), stats.netUpHistory.slice(-networkSamples)]
    for (var s = 0; s < series.length; s++)
      for (var i = 0; i < series[s].length; i++) if (series[s][i] > peak) peak = series[s][i]
    return peak
  }
  function networkSeries(history) {
    var peak = networkGraphPeak
    return history.slice(-networkSamples).map(function(rate) { return rate / peak })
  }

  function networkTooltip() {
    return translations.t("network.title") + "  ↓ " + rateText(stats.netDown) + "  ↑ " + rateText(stats.netUp)
  }

  // Ten megabytes a second fills the disk graph, more if the disk is doing
  // more, so idle chatter does not look like work.
  readonly property real diskGraphFloor: 10 * 1048576

  // The readings a history graph draws. Disk space hardly moves, so the
  // disk's graph is its activity, reads and writes together.
  function graphicValues(item) {
    if (!stats || style(item) !== "graph") return []
    // Above the line: what is being sent.
    if (item === "network") return networkSeries(stats.netUpHistory)
    if (item === "cpu") return stats.cpuHistory
    if (item === "gpu") return stats.gpuHistory
    if (item === "memory") return stats.memoryHistory
    var reads = stats.diskReadHistory.slice(-10)
    var writes = stats.diskWriteHistory.slice(-10)
    var totals = []
    var peak = diskGraphFloor
    for (var i = 0; i < reads.length; i++) {
      totals.push(reads[i] + (writes[i] || 0))
      if (totals[i] > peak) peak = totals[i]
    }
    return totals.map(function(total) { return total / peak })
  }

  // The fainter second part of the memory gauge: memory the kernel is only
  // using as cache.
  function graphicExtra(item) {
    if (item !== "memory" || !stats || !(stats.memory.total > 0)) return 0
    return stats.memory.cache / stats.memory.total
  }

  // Where the bar shows no number, hovering gives it.
  function barTooltip(item) {
    var value = reading(item)
    var chosen = style(item)
    var numbered = chosen === "percentage" || chosen === "icon and percentage" || chosen === "rates"
      || (drawn(item) && showPercentage)
    if (numbered || value < 0) return ""
    if (item === "network") return networkTooltip()
    return translations.t(item + ".title") + " " + percentText(value, 0)
  }

  TextMetrics {
    id: labelMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: "100%"
  }
  TextMetrics {
    id: rateMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Math.round(Style.bar.iconFont * 0.72)
    text: "↓999M"
  }
  // Wide enough for "100%", so neighbours never move as readings change.
  readonly property real labelSlot: Style.bar.iconSlot + Math.ceil(labelMetrics.advanceWidth) + Style.space(4)

  implicitWidth: buttons.implicitWidth
  implicitHeight: buttons.implicitHeight
  visible: items.length > 0

  Grid {
    id: buttons
    anchors.centerIn: parent
    flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
    rows: root.vertical ? Math.max(1, root.items.length) : 1
    columns: root.vertical ? 1 : Math.max(1, root.items.length)

    Repeater {
      id: buttonRepeater
      model: root.items

      BarIconButton {
        id: button

        required property string modelData
        readonly property string style: root.style(modelData)
        readonly property bool known: root.reading(modelData) >= 0
        // Graphs, gauges, pies and bare percentages are laid out below; the
        // two icon styles are the button's own icon and label.
        readonly property bool graphed: known && root.drawn(modelData)
        readonly property bool numbered: known
          && (style === "percentage" || style === "rates" || (graphed && root.showPercentage))
        readonly property bool network: modelData === "network"
        readonly property bool custom: graphed || numbered
        readonly property color ink: active ? root.urgent : root.foreground

        bar: root.bar
        text: custom ? "" : root.icons[modelData]
        hasVisualContent: true
        labelText: style === "icon and percentage" ? root.barLabel(modelData) : ""
        slotSize: custom ? reading.implicitWidth + Style.bar.iconSlot - Style.bar.iconCanvas
          : style === "icon and percentage" && known ? root.labelSlot
          : Style.bar.iconSlot
        active: root.alarming(modelData)
        dimmed: !known
        tooltipText: root.barTooltip(modelData)
        onPressed: function(button) {
          if (button === Qt.RightButton) {
            if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
            root.close()
          } else {
            root.show(modelData)
          }
        }

        Row {
          id: reading
          visible: button.custom
          anchors.centerIn: parent
          spacing: Style.space(4)
          scale: button.pressScale

          // Network rates, sent over received, small enough to stack.
          Column {
            visible: button.numbered && button.network
            anchors.verticalCenter: parent.verticalCenter
            spacing: -Style.space(1)

            Repeater {
              model: 2

              Text {
                required property int index
                width: Math.ceil(rateMetrics.advanceWidth)
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: (index === 0 ? "↑" : "↓")
                  + Model.rateCompact(root.stats ? (index === 0 ? root.stats.netUp : root.stats.netDown) : 0)
                font.family: root.fontFamily
                font.pixelSize: rateMetrics.font.pixelSize
                color: button.ink
                renderType: Text.NativeRendering
              }
            }
          }

          Text {
            visible: button.numbered && !button.network
            anchors.verticalCenter: parent.verticalCenter
            // As wide as "100%", so nothing shifts as the reading changes.
            width: Math.ceil(labelMetrics.advanceWidth)
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: root.percentText(Math.max(0, root.reading(button.modelData)), 0)
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
            color: button.ink
            renderType: Text.NativeRendering
          }

          BarGraphic {
            visible: button.graphed
            anchors.verticalCenter: parent.verticalCenter
            kind: root.graphicKind(button.modelData)
            color: button.ink
            values: root.graphicValues(button.modelData)
            secondary: button.network && root.stats ? root.networkSeries(root.stats.netDownHistory) : []
            fraction: Math.max(0, root.reading(button.modelData))
            extra: root.graphicExtra(button.modelData)
          }
        }
      }
    }
  }

  // Tells the bar which icon the open panel belongs to, so its mark sits
  // under that one rather than under the middle of the group.
  readonly property Item openPanelIndicatorItem: activeButton
  readonly property Item activeButton: {
    buttonRepeater.count  // re-evaluate as buttons come and go
    return buttonRepeater.itemAt(root.activeIndex) || buttons
  }

  Component { id: cpuView; CpuView { ctx: root } }
  Component { id: memoryView; MemoryView { ctx: root } }
  Component { id: gpuView; GpuView { ctx: root } }
  Component { id: diskView; DiskView { ctx: root } }
  Component { id: networkView; NetworkView { ctx: root } }

  KeyboardPanel {
    id: panel
    anchorItem: root.activeButton
    owner: root
    bar: root.bar
    open: root.opened && root.stats !== null && root.items.length > 0
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: viewLoader.item ? viewLoader.item.implicitHeight : 0
      // Left and Right walk the readings; Tab moves on to the next bar panel.
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.cycle(dx) }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Loader {
        id: viewLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        sourceComponent: !root.stats ? null
          : root.active === "memory" ? memoryView
          : root.active === "gpu" ? gpuView
          : root.active === "disk" ? diskView
          : root.active === "network" ? networkView
          : cpuView
      }
    }
  }
}
