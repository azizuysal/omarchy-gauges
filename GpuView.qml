import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Column {
  id: root

  required property var ctx
  readonly property var stats: ctx.stats
  readonly property var primary: stats.gpu

  spacing: Style.space(14)

  Hero {
    ctx: root.ctx
    icon: root.ctx.icons.gpu
    title: root.ctx.strings.t("gpu.title")
    caption: root.primary ? root.primary.name : (root.stats.gpus.length === 1 ? root.stats.gpus[0].name : "")
    value: root.primary ? root.ctx.percentText(root.primary.busy, 0) : ""
  }

  Sparkline {
    visible: root.primary !== null
    ctx: root.ctx
    values: root.stats.gpuHistory
    capacity: root.stats.historyLength
  }

  Label {
    visible: root.stats.gpus.length === 0
    ctx: root.ctx
    dim: true
    text: root.ctx.strings.t("gpu.none")
  }

  Repeater {
    model: root.stats.gpus

    Column {
      id: card
      required property var modelData
      required property int index
      readonly property var gpu: modelData

      width: root.width
      spacing: Style.space(8)

      PanelSeparator { foreground: root.ctx.foreground }

      Item {
        width: parent.width
        implicitHeight: nameHeader.implicitHeight

        PanelSectionHeader {
          id: nameHeader
          text: card.gpu.name
          foreground: root.ctx.foreground
          fontFamily: root.ctx.fontFamily
          elide: Text.ElideRight
          anchors.left: parent.left
          anchors.right: stateLabel.left
          anchors.rightMargin: Style.space(8)
        }

        Label {
          id: stateLabel
          ctx: root.ctx
          dim: true
          visible: card.gpu.asleep
          text: root.ctx.strings.t("gpu.asleep")
          font.pixelSize: Style.font.caption
          anchors.right: parent.right
          anchors.verticalCenter: nameHeader.verticalCenter
        }
      }

      Meter {
        visible: card.gpu.busy !== null && !card.gpu.asleep
        ctx: root.ctx
        fraction: card.gpu.busy === null ? 0 : card.gpu.busy
      }

      Column {
        visible: !card.gpu.asleep
        width: parent.width
        spacing: Style.spacing.labelGap

        StatRow {
          visible: card.gpu.busy !== null
          ctx: root.ctx
          label: root.ctx.strings.t("gpu.usage")
          value: card.gpu.busy === null ? "" : root.ctx.percentText(card.gpu.busy, 0)
        }
        StatRow {
          visible: card.gpu.vramTotal > 0
          ctx: root.ctx
          label: root.ctx.strings.t("gpu.memory")
          value: card.gpu.vramTotal > 0
            ? root.ctx.strings.t("common.of").arg(root.ctx.bytesText(card.gpu.vramUsed)).arg(root.ctx.bytesText(card.gpu.vramTotal)) : ""
        }
        StatRow {
          visible: card.gpu.temp !== null
          ctx: root.ctx
          label: root.ctx.strings.t("common.temperature")
          value: root.ctx.tempText(card.gpu.temp)
          valueColor: root.ctx.levelColor(card.gpu.temp === null ? 0 : card.gpu.temp / 100, 0.95)
        }
        StatRow {
          visible: card.gpu.power !== null
          ctx: root.ctx
          label: root.ctx.strings.t("gpu.power")
          value: card.gpu.power === null ? "" : root.ctx.strings.t("gpu.watts").arg(Commons.I18n.formatNumber(card.gpu.power, 1))
        }
        StatRow {
          visible: card.gpu.freq !== null
          ctx: root.ctx
          label: root.ctx.strings.t("gpu.frequency")
          value: card.gpu.freq === null ? "" : root.ctx.strings.t("gpu.megahertz").arg(Commons.I18n.formatNumber(card.gpu.freq))
        }
      }
    }
  }
}
