import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  required property var ctx
  readonly property var stats: ctx.stats
  // The interfaces with a link, which is where any traffic is.
  readonly property var connected: stats.netInterfaces.filter(function(entry) { return entry.state !== "down" })

  readonly property real unattributed: {
    var listed = 0
    for (var i = 0; i < stats.netPrograms.length; i++) listed += stats.netPrograms[i].down + stats.netPrograms[i].up
    return Math.max(0, stats.netDown + stats.netUp - listed)
  }

  spacing: Style.space(14)

  Hero {
    ctx: root.ctx
    icon: root.ctx.icons.network
    title: root.ctx.strings.t("network.title")
    caption: root.connected.map(function(entry) { return entry.name }).join("  ")
    value: root.stats.netReady ? root.ctx.rateText(root.stats.netDown + root.stats.netUp) : ""
  }

  // Download is the filled line, upload the fainter one. Scaled to the
  // busiest moment in view, with a floor so background chatter stays flat.
  Sparkline {
    ctx: root.ctx
    values: root.stats.netDownHistory
    secondary: root.stats.netUpHistory
    ceiling: 0
    floor: 131072
    capacity: root.stats.historyLength
  }

  Row {
    width: parent.width
    spacing: Style.space(20)

    StatRow {
      width: (parent.width - parent.spacing) / 2
      ctx: root.ctx
      label: root.ctx.strings.t("network.download")
      value: root.ctx.rateText(root.stats.netDown)
    }

    StatRow {
      width: (parent.width - parent.spacing) / 2
      ctx: root.ctx
      label: root.ctx.strings.t("network.upload")
      value: root.ctx.rateText(root.stats.netUp)
    }
  }

  PanelSeparator { foreground: root.ctx.foreground }

  // Who the traffic belongs to, as far as an ordinary user can be told: see
  // Model.parseSockets for what is and is not visible.
  Column {
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: root.ctx.strings.t("network.top")
      foreground: root.ctx.foreground
      fontFamily: root.ctx.fontFamily
    }

    Column {
      width: parent.width
      spacing: Style.spacing.labelGap

      Repeater {
        model: root.stats.netPrograms

        StatRow {
          required property var modelData
          ctx: root.ctx
          label: modelData.name
          value: root.ctx.strings.t("network.updown").arg(root.ctx.rateText(modelData.down)).arg(root.ctx.rateText(modelData.up))
        }
      }

      // What the interfaces carried that no listed program accounts for.
      StatRow {
        visible: root.stats.netProgramsReady && root.unattributed >= 1024
        ctx: root.ctx
        label: root.ctx.strings.t("network.other")
        value: root.ctx.rateText(root.unattributed)
      }

      Label {
        visible: root.stats.netPrograms.length === 0 && !(root.stats.netProgramsReady && root.unattributed >= 1024)
        ctx: root.ctx
        dim: true
        text: root.ctx.strings.t(root.stats.netProgramsReady ? "network.quiet" : "common.measuring")
      }
    }

    Label {
      ctx: root.ctx
      dim: true
      width: parent.width
      wrapMode: Text.WordWrap
      font.pixelSize: Style.font.caption
      text: root.ctx.strings.t("network.topNote")
    }
  }

  PanelSeparator { foreground: root.ctx.foreground }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: root.ctx.strings.t("network.interfaces")
      foreground: root.ctx.foreground
      fontFamily: root.ctx.fontFamily
    }

    Label {
      visible: root.stats.netInterfaces.length === 0
      ctx: root.ctx
      dim: true
      text: root.ctx.strings.t("network.none")
    }

    Repeater {
      model: root.stats.netInterfaces

      Column {
        id: entry
        required property var modelData
        readonly property bool down: modelData.state === "down"

        width: root.width
        spacing: Style.spacing.labelGap
        opacity: down ? 0.5 : 1

        StatRow {
          ctx: root.ctx
          label: entry.modelData.name
          value: entry.down ? root.ctx.strings.t("network.down")
            : root.ctx.strings.t("network.updown").arg(root.ctx.rateText(entry.modelData.down)).arg(root.ctx.rateText(entry.modelData.up))
        }

        StatRow {
          visible: !entry.down
          ctx: root.ctx
          label: root.ctx.strings.t("network.sinceBoot")
          value: root.ctx.strings.t("network.updown").arg(root.ctx.bytesText(entry.modelData.received)).arg(root.ctx.bytesText(entry.modelData.sent))
        }
      }
    }
  }
}
