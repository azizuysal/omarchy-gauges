import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The bar item: one icon and reading per metric, each opening the same
// popup on its own detail view. Readings come from Service.qml, which the
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
  readonly property var allItems: ["cpu", "memory", "gpu", "disk"]

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
  readonly property bool showValues: setting("showValues", true) !== false && !vertical
  // A property of its own so `items` only changes when a card appears or
  // goes, not on every sample: a new list rebuilds every bar button.
  readonly property bool hasGpu: stats ? stats.gpus.length > 0 : false
  readonly property var items: {
    var chosen = setting("items", [])
    if (!Array.isArray(chosen) || chosen.length === 0) chosen = allItems
    // Keep the canonical order whatever order they were ticked in.
    return allItems.filter(function(item) {
      return chosen.indexOf(item) !== -1 && (item !== "gpu" || hasGpu)
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
  onStatsChanged: { watching = false; syncWatch() }
  Component.onDestruction: if (watching && stats) stats.watchProcesses(false)

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
    disk: String.fromCodePoint(0xF02CA)
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
    return (item === "memory" || item === "disk") && reading(item) >= 0.9
  }

  TextMetrics {
    id: labelMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: "100%"
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
        required property string modelData
        readonly property string label: root.showValues ? root.barLabel(modelData) : ""

        bar: root.bar
        text: root.icons[modelData]
        labelText: label
        slotSize: root.showValues && root.reading(modelData) >= 0 ? root.labelSlot : Style.bar.iconSlot
        active: root.alarming(modelData)
        dimmed: root.reading(modelData) < 0
        tooltipText: ""
        onPressed: function(button) {
          if (button === Qt.RightButton) {
            if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
            root.close()
          } else {
            root.show(modelData)
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
          : cpuView
      }
    }
  }
}
