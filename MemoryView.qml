import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  required property var ctx
  readonly property var stats: ctx.stats
  readonly property var memory: stats.memory

  spacing: Style.space(14)

  Hero {
    ctx: root.ctx
    icon: root.ctx.icons.memory
    title: root.ctx.strings.t("memory.title")
    caption: root.memory.total > 0 ? root.ctx.strings.t("memory.total").arg(root.ctx.bytesText(root.memory.total)) : ""
    value: root.memory.total > 0 ? root.ctx.percentText(root.memory.fraction, 0) : ""
    valueColor: root.ctx.levelColor(root.memory.fraction, 0.9)
  }

  // Solid for what programs hold, faint for cache the kernel would give back.
  Meter {
    ctx: root.ctx
    fraction: root.memory.fraction
    extra: root.memory.total > 0 ? root.memory.cache / root.memory.total : 0
    fillColor: root.ctx.levelColor(root.memory.fraction, 0.9)
  }

  Sparkline {
    ctx: root.ctx
    values: root.stats.memoryHistory
    capacity: root.stats.historyLength
  }

  Row {
    width: parent.width
    spacing: Style.space(20)

    Column {
      width: (parent.width - parent.spacing) / 2
      spacing: Style.spacing.labelGap
      StatRow { ctx: root.ctx; label: root.ctx.strings.t("memory.used"); value: root.ctx.bytesText(root.memory.used) }
      StatRow { ctx: root.ctx; label: root.ctx.strings.t("memory.cached"); value: root.ctx.bytesText(root.memory.cache) }
    }

    Column {
      width: (parent.width - parent.spacing) / 2
      spacing: Style.spacing.labelGap
      StatRow { ctx: root.ctx; label: root.ctx.strings.t("memory.available"); value: root.ctx.bytesText(root.memory.available) }
      StatRow {
        ctx: root.ctx
        label: root.ctx.strings.t("memory.swap")
        value: root.memory.swapTotal > 0 ? root.ctx.bytesText(root.memory.swapUsed) : root.ctx.strings.t("memory.noSwap")
        valueColor: root.ctx.levelColor(root.memory.swapFraction, 0.8)
      }
    }
  }

  PanelSeparator { foreground: root.ctx.foreground }

  ProcessList {
    ctx: root.ctx
    title: root.ctx.strings.t("memory.top")
    rows: root.stats.topByMemory
    kind: "memory"
  }
}
