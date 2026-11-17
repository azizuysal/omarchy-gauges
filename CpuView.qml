import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Column {
  id: root

  required property var ctx
  readonly property var stats: ctx.stats

  spacing: Style.space(14)

  Hero {
    ctx: root.ctx
    icon: root.ctx.icons.cpu
    title: root.ctx.strings.t("cpu.title")
    caption: root.stats.cpuModel
    value: root.stats.ready ? root.ctx.percentText(root.stats.cpuUsage, 0) : ""
    valueColor: root.ctx.levelColor(root.stats.cpuUsage, 0.9)
  }

  Sparkline {
    ctx: root.ctx
    values: root.stats.cpuHistory
    capacity: root.stats.historyLength
  }

  Column {
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: root.ctx.strings.t("cpu.cores")
      foreground: root.ctx.foreground
      fontFamily: root.ctx.fontFamily
    }

    CoreBars {
      ctx: root.ctx
      cores: root.stats.cpuCores
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(20)

    Column {
      width: (parent.width - parent.spacing) / 2
      spacing: Style.spacing.labelGap
      StatRow { ctx: root.ctx; label: root.ctx.strings.t("cpu.user"); value: root.stats.ready ? root.ctx.percentText(root.stats.cpuUser, 0) : "" }
      StatRow { ctx: root.ctx; label: root.ctx.strings.t("cpu.system"); value: root.stats.ready ? root.ctx.percentText(root.stats.cpuSystem, 0) : "" }
      StatRow {
        ctx: root.ctx
        label: root.ctx.strings.t("common.temperature")
        value: root.ctx.tempText(root.stats.cpuTemp)
        valueColor: root.ctx.levelColor(root.stats.cpuTemp === null ? 0 : root.stats.cpuTemp / 100, 0.95)
      }
    }

    Column {
      width: (parent.width - parent.spacing) / 2
      spacing: Style.spacing.labelGap
      StatRow {
        ctx: root.ctx
        label: root.ctx.strings.t("cpu.load")
        value: Commons.I18n.formatNumber(root.stats.load.one, 2) + "  " + Commons.I18n.formatNumber(root.stats.load.five, 2)
      }
      StatRow { ctx: root.ctx; label: root.ctx.strings.t("cpu.tasks"); value: Commons.I18n.formatNumber(root.stats.load.tasks) }
      StatRow { ctx: root.ctx; label: root.ctx.strings.t("cpu.uptime"); value: root.ctx.uptimeText(root.stats.uptime) }
    }
  }

  PanelSeparator { foreground: root.ctx.foreground }

  ProcessList {
    ctx: root.ctx
    title: root.ctx.strings.t("cpu.top")
    rows: root.stats.topByCpu
    kind: "cpu"
  }
}
