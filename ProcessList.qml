import QtQuick
import qs.Commons
import qs.Ui

// The heaviest programs, each with its processes added together.
Column {
  id: root

  property var ctx: null
  property string title: ""
  property var rows: []
  // "cpu" and "gpu" print a percentage, "memory" a size, "disk" the speeds
  // of reading and writing.
  property string kind: "cpu"
  // Once the rows have been measured, an empty list means nothing is busy
  // and says so with `quiet`; until then it says it is measuring.
  property bool ready: false
  property string quiet: ""

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  PanelSectionHeader {
    text: root.title
    foreground: root.ctx ? root.ctx.foreground : "transparent"
    fontFamily: root.ctx ? root.ctx.fontFamily : Style.font.family
  }

  Column {
    width: parent.width
    spacing: Style.spacing.labelGap

    Repeater {
      model: root.rows

      StatRow {
        required property var modelData
        ctx: root.ctx
        label: modelData.count > 1 ? modelData.name + " ×" + modelData.count : modelData.name
        value: root.kind === "cpu" ? root.ctx.percentText(modelData.cpu / 100, 1)
          : root.kind === "gpu" ? root.ctx.percentText(modelData.load, 1)
          : root.kind === "disk" ? root.ctx.strings.t("disk.readwrite").arg(root.ctx.rateText(modelData.read)).arg(root.ctx.rateText(modelData.write))
          : root.ctx.bytesText(modelData.memory)
      }
    }

    Label {
      visible: root.rows.length === 0
      ctx: root.ctx
      dim: true
      text: !root.ctx ? "" : root.ready && root.quiet !== "" ? root.quiet : root.ctx.strings.t("common.measuring")
    }
  }
}
