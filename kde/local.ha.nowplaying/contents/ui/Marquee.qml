/*
 * One line of text that scrolls when it doesn't fit (marquee).
 *
 * Text that fits stays still. Longer text holds for `holdMs`, scrolls left at
 * `speed` px/s until a second copy (one `gap` behind) reaches the start, and
 * repeats - a seamless loop. A new text starts again from the hold.
 * naturalWidth is the unclipped width, for sizing the panel around it.
 */
import QtQuick

Item {
    id: m

    property string text
    property color color: "white"
    // Hard 1 px shadow under the text (Text.Raised); transparent = none.
    property color styleColor: "transparent"
    property font font
    property real speed: 40
    property int holdMs: 2000
    property real gap: 56
    readonly property real naturalWidth: label.implicitWidth
    readonly property bool scrolling: label.implicitWidth > width + 0.5
    readonly property real offset: strip.x

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    clip: true

    Item {
        id: strip
        height: m.height
        Text {
            id: label
            text: m.text
            color: m.color
            font: m.font
            renderType: Text.NativeRendering
            style: Text.Raised
            styleColor: m.styleColor
        }
        Text {
            x: Math.ceil(label.implicitWidth + m.gap)
            visible: m.scrolling
            text: m.text
            color: m.color
            font: m.font
            renderType: Text.NativeRendering
            style: Text.Raised
            styleColor: m.styleColor
        }
    }

    SequentialAnimation {
        id: anim
        loops: Animation.Infinite
        running: m.scrolling && m.visible
        PauseAnimation { duration: m.holdMs }
        NumberAnimation {
            target: strip
            property: "x"
            from: 0
            to: -Math.ceil(label.implicitWidth + m.gap)
            duration: Math.max(1, 1000 * (label.implicitWidth + m.gap) / Math.max(1, m.speed))
        }
        onRunningChanged: if (!running) strip.x = 0
    }

    function restart() {
        strip.x = 0
        if (anim.running) anim.restart()
    }
    onTextChanged: restart()
    onWidthChanged: restart()
}
