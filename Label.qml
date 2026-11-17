import QtQuick
import qs.Commons

// Body text for the panels. PlainText always: process names, mount points
// and device names come from the system and must never be read as markup.
Text {
  property var ctx: null
  property bool dim: false

  textFormat: Text.PlainText
  color: ctx ? (dim ? ctx.dim : ctx.foreground) : "transparent"
  font.family: ctx ? ctx.fontFamily : Style.font.family
  font.pixelSize: Style.font.bodySmall
  elide: Text.ElideRight
}
