import QtQuick
import qs.Ui
import qs.Commons
import "MediaModel.js" as MediaModel

// "Advanced options" view shown inside the popup. It only reads the
// preferences it is given and reports changes upward; persistence lives in
// Service.qml. Built from the shell's own controls (ToggleSwitch, ButtonGroup,
// NumberField, PanelSectionHeader) so it looks like the other Omarchy panels.
//
// Layout is kept short on purpose (small screens): a fixed header + preview,
// then one tab at a time, with the simple switches laid out in two columns.
Column {
  id: root

  property var prefs: ({})
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // Current track, used by the live preview.
  property string sampleTitle: ""
  property string sampleArtist: ""
  property string sampleAlbum: ""
  property string samplePlayer: ""

  // "content" | "format" | "size"
  property string tab: "content"

  signal changed(string name, var value)
  signal resetRequested()
  signal backRequested()

  spacing: Style.space(8)

  readonly property bool fitText: prefs.dynamicWidth === true
  readonly property bool cutMode: prefs.textMode === "ellipsis"

  // "Name ........ control" line, optionally with a small explanation.
  component Option: Item {
    id: opt
    property color fg: Color.foreground
    property string family: Style.font.family
    property string label: ""
    property string hint: ""
    default property alias control: controlHolder.children

    width: parent ? parent.width : 0
    height: Math.max(textCol.implicitHeight, controlHolder.implicitHeight)

    Column {
      id: textCol
      anchors.left: parent.left
      anchors.right: controlHolder.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: opt.label
        color: opt.fg
        font.family: opt.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: opt.hint !== ""
        text: opt.hint
        color: Qt.darker(opt.fg, 1.5)
        font.family: opt.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Row {
      id: controlHolder
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
    }
  }

  // Half-width "Name [switch]" cell for the two-column grid.
  component Cell: Item {
    id: cell
    property color fg: Color.foreground
    property string family: Style.font.family
    property string label: ""
    default property alias control: cellControl.children

    width: parent ? (parent.width - parent.columnSpacing) / 2 : 0
    height: Math.max(cellLabel.implicitHeight, cellControl.implicitHeight)

    Text {
      id: cellLabel
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: cellControl.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: cell.label
      color: cell.fg
      font.family: cell.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Row {
      id: cellControl
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // Small explanation under a control.
  component Hint: Text {
    property color fg: Color.foreground
    property string family: Style.font.family
    textFormat: Text.PlainText
    color: Qt.darker(fg, 1.5)
    font.family: family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // --- header ---------------------------------------------------------------

  Item {
    width: parent.width
    height: backButton.implicitHeight

    Button {
      id: backButton
      iconText: "󰁍"
      foreground: root.foreground
      horizontalPadding: Style.spacing.controlPaddingX
      verticalPadding: Style.spacing.controlPaddingY
      tooltipText: "Back"
      onClicked: root.backRequested()
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: backButton.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: "Advanced options"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Button {
      anchors.right: parent.right
      text: "Reset"
      foreground: Qt.darker(root.foreground, 1.4)
      horizontalPadding: Style.spacing.controlPaddingX
      verticalPadding: Style.spacing.controlPaddingY
      tooltipText: "Restore the default options"
      onClicked: root.resetRequested()
    }
  }

  // --- live preview ---------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(3)

    Rectangle {
      id: previewBox
      width: parent.width
      height: Style.space(32)
      radius: Style.spacing.labelGap
      color: Util.alpha(root.foreground, 0.08)
      border.width: Style.space(1)
      border.color: Util.alpha(root.foreground, 0.25)
      clip: true

      readonly property string previewString: MediaModel.barLabel({
        title: root.sampleTitle || "Song title",
        artist: root.sampleArtist || "Artist name",
        album: root.sampleAlbum || "Album name",
        player: root.samplePlayer || "Player"
      }, root.prefs)

      // What the widget would really take in the bar (the box above can't
      // show more than the popup's width).
      readonly property int barWidth: Math.round(
        (previewCover.visible ? previewCover.width + Style.space(6) : 0)
        + (previewTime.visible ? previewTime.implicitWidth + Style.space(6) : 0)
        + (previewPrev.visible ? previewPrev.implicitWidth + Style.space(6) : 0)
        + (previewNext.visible ? previewNext.implicitWidth + Style.space(6) : 0)
        + (previewGlyph.visible ? previewGlyph.implicitWidth + Style.space(6) : 0)
        + (previewString === "" ? 0 : (root.fitText ? previewLabel.implicitWidth : root.prefs.maxWidth))
        + Style.space(14))

      Row {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Rectangle {
          id: previewCover
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          height: width
          radius: Style.space(3)
          visible: root.prefs.showCover
          color: Util.alpha(root.foreground, 0.25)

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "󰝚"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: previewPrev
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          visible: root.prefs.showPrevious
          text: "󰒮"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: previewGlyph
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          visible: root.prefs.showIcon || (previewBox.previewString === "" && !previewCover.visible && !previewTime.visible && !previewPrev.visible && !previewNext.visible)
          text: "󰏤"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: previewNext
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          visible: root.prefs.showNext
          text: "󰒭"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Item {
          id: previewClip
          height: previewGlyph.implicitHeight
          anchors.verticalCenter: parent.verticalCenter
          clip: true
          visible: previewBox.previewString !== ""
          // The box can't show more than its own width, whatever the setting.
          width: Math.min(previewBox.width - Style.space(50),
            root.fitText ? previewLabel.implicitWidth : root.prefs.maxWidth)

          Text {
            id: previewLabel
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: previewBox.previewString
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            // Only a fixed width in scroll mode moves. Fitting the text or cutting
            // it never scrolls; when the popup is too narrow to show all of it,
            // the end is elided instead.
            elide: root.fitText || root.cutMode ? Text.ElideRight : Text.ElideNone
            width: root.fitText || root.cutMode ? previewClip.width : implicitWidth

            property bool needsScroll: !root.fitText && !root.cutMode && implicitWidth > previewClip.width

            NumberAnimation on x {
              running: previewLabel.needsScroll
              loops: Animation.Infinite
              duration: Math.max(6000, previewLabel.implicitWidth * 25)
              from: previewClip.width
              to: -previewLabel.implicitWidth
              easing.type: Easing.Linear
              onRunningChanged: if (!running) previewLabel.x = 0
            }
          }
        }

        Text {
          id: previewTime
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          visible: root.prefs.showTime
          text: "1:23 / 3:45"
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    Hint {
      width: parent.width
      fg: root.foreground; family: root.fontFamily
      text: "Space taken in the bar: about " + previewBox.barWidth + " px"
    }
  }

  // --- tabs -----------------------------------------------------------------

  ButtonGroup {
    foreground: root.foreground
    fontFamily: root.fontFamily
    options: [
      { value: "content", label: "Content" },
      { value: "format", label: "Format" },
      { value: "size", label: "Size" },
      { value: "visualizer", label: "Visuals" }
    ]
    value: root.tab
    onChanged: function(v) { root.tab = v }
  }

  // --- tab: content ---------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.tab === "content"

    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Style.space(16)
      rowSpacing: Style.space(8)

      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Icon"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showIcon; onToggled: root.changed("showIcon", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Cover"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showCover; onToggled: root.changed("showCover", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Previous"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showPrevious; onToggled: root.changed("showPrevious", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Next"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showNext; onToggled: root.changed("showNext", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Title"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showTitle; onToggled: root.changed("showTitle", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Artist"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showArtist; onToggled: root.changed("showArtist", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Album"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showAlbum; onToggled: root.changed("showAlbum", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Player"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showPlayer; onToggled: root.changed("showPlayer", !checked) }
      }
      Cell {
        fg: root.foreground; family: root.fontFamily; label: "Time"
        ToggleSwitch { foreground: root.foreground; checked: root.prefs.showTime; onToggled: root.changed("showTime", !checked) }
      }
    }

    PanelSeparator { foreground: root.foreground }

    Option {
      fg: root.foreground; family: root.fontFamily
      label: "Hide when paused"
      hint: "The widget disappears while nothing plays"
      ToggleSwitch { foreground: root.foreground; checked: root.prefs.hideWhenPaused; onToggled: root.changed("hideWhenPaused", !checked) }
    }
  }

  // --- tab: format ----------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(10)
    visible: root.tab === "format"

    Option {
      fg: root.foreground; family: root.fontFamily
      label: "Order"
      ButtonGroup {
        foreground: root.foreground
        fontFamily: root.fontFamily
        options: [
          { value: "title", label: "Title" },
          { value: "artist", label: "Artist" }
        ]
        value: root.prefs.artistFirst ? "artist" : "title"
        onChanged: function(v) { root.changed("artistFirst", v === "artist") }
      }
    }

    Option {
      fg: root.foreground; family: root.fontFamily
      label: "Separator"
      ButtonGroup {
        foreground: root.foreground
        fontFamily: root.fontFamily
        options: [
          { value: "·", label: "·" },
          { value: "-", label: "-" },
          { value: "|", label: "|" },
          { value: "/", label: "/" }
        ]
        value: root.prefs.separator
        onChanged: function(v) { root.changed("separator", v) }
      }
    }
  }

  // --- tab: visualizer ------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(10)
    visible: root.tab === "visualizer"

    Option {
      fg: root.foreground; family: root.fontFamily
      label: "In the bar"
      hint: "Behind the widget's text"
      ToggleSwitch { foreground: root.foreground; checked: root.prefs.vizBar; onToggled: root.changed("vizBar", !checked) }
    }

    Option {
      fg: root.foreground; family: root.fontFamily
      label: "In the popup"
      hint: "Behind the controls, fainter"
      ToggleSwitch { foreground: root.foreground; checked: root.prefs.vizPopup; onToggled: root.changed("vizPopup", !checked) }
    }

    PanelSeparator { foreground: root.foreground }

    Option {
      fg: root.foreground; family: root.fontFamily
      label: "Style"
      ButtonGroup {
        foreground: root.foreground
        fontFamily: root.fontFamily
        options: [
          { value: "bars", label: "Bars" },
          { value: "wave", label: "Wave" },
          { value: "mirror", label: "Mirror" }
        ]
        value: root.prefs.vizStyle
        onChanged: function(v) { root.changed("vizStyle", v) }
      }
    }

    Hint {
      width: parent.width
      fg: root.foreground; family: root.fontFamily
      text: "It moves only while something plays. Bass on the left, treble on the right."
    }
  }

  // --- tab: size ------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.tab === "size"

    ButtonGroup {
      foreground: root.foreground
      fontFamily: root.fontFamily
      options: [
        { value: "fit", label: "Fit the text" },
        { value: "fixed", label: "Fixed width" }
      ]
      value: root.fitText ? "fit" : "fixed"
      onChanged: function(v) { root.changed("dynamicWidth", v === "fit") }
    }

    Hint {
      visible: root.fitText
      width: parent.width
      fg: root.foreground; family: root.fontFamily
      text: "The widget always shows the whole text and grows or shrinks with it."
    }

    // Everything below only makes sense with a fixed width: when the widget
    // fits the text there is no limit to exceed, so nothing is scrolled or cut.
    Option {
      visible: !root.fitText
      fg: root.foreground; family: root.fontFamily
      label: "Width"
      NumberField {
        foreground: root.foreground
        fontFamily: root.fontFamily
        value: root.prefs.maxWidth
        from: 60
        to: 600
        stepSize: 20
        onModified: function(v) { root.changed("maxWidth", v) }
      }
    }

    Option {
      visible: !root.fitText
      fg: root.foreground; family: root.fontFamily
      label: "Long text"
      ButtonGroup {
        foreground: root.foreground
        fontFamily: root.fontFamily
        options: [
          { value: "scroll", label: "Scroll" },
          { value: "ellipsis", label: "Cut ..." }
        ]
        value: root.cutMode ? "ellipsis" : "scroll"
        onChanged: function(v) { root.changed("textMode", v) }
      }
    }

    Option {
      visible: !root.fitText && root.cutMode
      fg: root.foreground; family: root.fontFamily
      label: "Character limit"
      NumberField {
        foreground: root.foreground
        fontFamily: root.fontFamily
        value: root.prefs.maxChars
        from: 5
        to: 200
        stepSize: 5
        onModified: function(v) { root.changed("maxChars", v) }
      }
    }
  }
}
