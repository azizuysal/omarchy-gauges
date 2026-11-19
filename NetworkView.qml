import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  required property var ctx
  readonly property var stats: ctx.stats
  // The interfaces with a link, which is where any traffic is.
  readonly property var connected: stats.netInterfaces.filter(function(entry) { return root.stateOf(entry) === "up" })

  // "down" with no link, "idle" with a link but no address on it (a cable
  // into something that hands none out), otherwise "up". Until the addresses
  // have been read, a link counts as up.
  function stateOf(entry) {
    if (entry.state === "down") return "down"
    var addresses = stats.netAddresses[entry.name]
    return addresses && addresses.v4.length === 0 && addresses.v6.length === 0 ? "idle" : "up"
  }

  function kindOf(entry) {
    return ctx.strings.t(entry.wireless ? "network.wifi" : "network.ethernet")
  }

  spacing: Style.space(14)

  Hero {
    ctx: root.ctx
    icon: root.ctx.icons.network
    title: root.ctx.strings.t("network.title")
    // The kind of link doing the work: of those that are up, the one that
    // has carried the most.
    caption: {
      var busiest = null
      for (var i = 0; i < root.connected.length; i++) {
        var entry = root.connected[i]
        if (!busiest || entry.received + entry.sent > busiest.received + busiest.sent) busiest = entry
      }
      return busiest ? root.kindOf(busiest) : ""
    }
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

  AddressRow {
    visible: root.ctx.showPublicAddress
    ctx: root.ctx
    label: root.ctx.strings.t("network.public")
    address: root.stats.publicAddress
    prefix: Model.flagEmoji(root.stats.publicCountry)
    placeholder: root.ctx.strings.t(root.stats.publicState === "failed" ? "network.unavailable" : "network.lookingUp")
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
        readonly property string state: root.stateOf(modelData)
        readonly property bool down: state !== "up"
        readonly property var addresses: root.stats.netAddresses[modelData.name] || ({ v4: [], v6: [] })

        width: root.width
        spacing: Style.spacing.labelGap
        opacity: down ? 0.5 : 1

        StatRow {
          ctx: root.ctx
          label: root.kindOf(entry.modelData) + " · " + entry.modelData.name
          value: entry.state === "down" ? root.ctx.strings.t("network.down")
            : entry.state === "idle" ? root.ctx.strings.t("network.noAddress")
            : root.ctx.strings.t("network.updown").arg(root.ctx.rateText(entry.modelData.down)).arg(root.ctx.rateText(entry.modelData.up))
        }

        StatRow {
          visible: !entry.down
          ctx: root.ctx
          label: root.ctx.strings.t("network.sinceBoot")
          value: root.ctx.strings.t("network.updown").arg(root.ctx.bytesText(entry.modelData.received)).arg(root.ctx.bytesText(entry.modelData.sent))
        }

        AddressRow {
          visible: !entry.down && address !== ""
          ctx: root.ctx
          label: root.ctx.strings.t("network.address")
          address: entry.addresses.v4.length > 0 ? entry.addresses.v4[0] : ""
        }

        AddressRow {
          visible: root.ctx.showIPv6 && !entry.down && address !== ""
          ctx: root.ctx
          label: root.ctx.strings.t("network.ipv6")
          // One reachable from outside before one that only works at home.
          address: {
            var list = entry.addresses.v6
            for (var i = 0; i < list.length; i++) if (!/^f[cd]/i.test(list[i])) return list[i]
            return list.length > 0 ? list[0] : ""
          }
        }
      }
    }
  }

  PanelSeparator { foreground: root.ctx.foreground }

  // Who the traffic belongs to.
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
          // Packets nethogs could not tie to a program are background
          // chatter (name lookups, discovery) unless there are a lot of them.
          visible: !modelData.unknown || modelData.down + modelData.up >= 16384
          label: modelData.unknown ? root.ctx.strings.t("network.unidentified") : modelData.name
          value: root.ctx.strings.t("network.updown").arg(root.ctx.rateText(modelData.down)).arg(root.ctx.rateText(modelData.up))
        }
      }

      Label {
        visible: root.stats.netPrograms.length === 0
        ctx: root.ctx
        dim: true
        text: root.ctx.strings.t(root.stats.netProgramsReady ? "network.quiet" : "common.measuring")
      }
    }
  }
}
