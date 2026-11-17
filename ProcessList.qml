import QtQuick
import qs.Commons
import qs.Ui

// The heaviest programs, each with its processes added together.
Column {
  id: root

  property var ctx: null
  property string title: ""
  property var rows: []
  // "cpu" prints a percentage, "memory" a size.
  property string kind: "cpu"

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
        value: root.kind === "cpu" ? root.ctx.percentText(modelData.cpu / 100, 1) : root.ctx.bytesText(modelData.memory)
      }
    }

    Label {
      visible: root.rows.length === 0
      ctx: root.ctx
      dim: true
      text: root.ctx ? root.ctx.strings.t("common.measuring") : ""
    }
  }
}
