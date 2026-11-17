import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  required property var ctx
  readonly property var stats: ctx.stats
  readonly property var primary: stats.filesystem

  spacing: Style.space(14)

  Hero {
    ctx: root.ctx
    icon: root.ctx.icons.disk
    title: root.ctx.strings.t("disk.title")
    caption: root.primary ? root.ctx.strings.t("disk.free").arg(root.ctx.bytesText(root.primary.available)) : ""
    value: root.primary ? root.ctx.percentText(root.primary.fraction, 0) : ""
    valueColor: root.ctx.levelColor(root.primary ? root.primary.fraction : 0, 0.9)
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: root.ctx.strings.t("disk.volumes")
      foreground: root.ctx.foreground
      fontFamily: root.ctx.fontFamily
    }

    Label {
      visible: root.stats.filesystems.length === 0
      ctx: root.ctx
      dim: true
      text: root.ctx.strings.t("disk.none")
    }

    Repeater {
      model: root.stats.filesystems

      Column {
        id: volume
        required property var modelData

        width: root.width
        spacing: Style.space(5)

        StatRow {
          ctx: root.ctx
          label: volume.modelData.mount
          value: root.ctx.strings.t("common.of").arg(root.ctx.bytesText(volume.modelData.used)).arg(root.ctx.bytesText(volume.modelData.total))
        }

        Meter {
          ctx: root.ctx
          fraction: volume.modelData.fraction
          fillColor: root.ctx.levelColor(volume.modelData.fraction, 0.9)
        }
      }
    }
  }

  PanelSeparator { foreground: root.ctx.foreground }

  Column {
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: root.ctx.strings.t("disk.activity")
      foreground: root.ctx.foreground
      fontFamily: root.ctx.fontFamily
    }

    // Reads are the filled line, writes the fainter one. Scaled to the
    // busiest moment in view, with a floor so idle trickle stays flat.
    Sparkline {
      ctx: root.ctx
      values: root.stats.diskReadHistory
      secondary: root.stats.diskWriteHistory
      ceiling: 0
      floor: 1048576
      capacity: root.stats.historyLength
    }

    Row {
      width: parent.width
      spacing: Style.space(20)

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.spacing.labelGap
        StatRow { ctx: root.ctx; label: root.ctx.strings.t("disk.read"); value: root.ctx.rateText(root.stats.diskRead) }
        StatRow {
          visible: root.stats.diskTemps.length > 0
          ctx: root.ctx
          label: root.ctx.strings.t("common.temperature")
          value: root.stats.diskTemps.map(function(t) { return root.ctx.tempText(t) }).join("  ")
        }
      }

      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.spacing.labelGap
        StatRow { ctx: root.ctx; label: root.ctx.strings.t("disk.write"); value: root.ctx.rateText(root.stats.diskWrite) }
      }
    }
  }
}
