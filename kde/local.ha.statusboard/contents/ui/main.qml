/*
 * HA Status Board - KDE Plasma 6 port of the Rainmeter skin from
 * https://github.com/VagueDustin/rainmeter-homeassistant (MIT).
 *
 * A clock with two rows underneath, both driven entirely by
 * /local/statusboard.json from the unchanged Home Assistant package:
 *   STATS  up to 4 slots, a label over a value
 *   CHIPS  up to 6 slots, a coloured name over a sub-line
 * Empty slots hide, empty rows collapse, and the panel follows: it is as
 * wide as its content (capped by panelWidth and the widget's own width)
 * and as tall, so there is no empty band around a short board.
 * Time and date come from this machine, so the clock keeps ticking if HA
 * goes away.
 *
 * Sharpness: every size goes through px() (uiScale) and fs() (never under
 * minTextSize), so the board can be scaled up for a projector or TV. Text is
 * drawn hinted (NativeRendering, full hinting) with a 1 px raised shadow; a
 * blurred halo rendered through a layer left a haze around every letter, which
 * a large 1080p screen makes very visible.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property var cfg: Plasmoid.configuration
    readonly property string haUrl: (cfg.haUrl || "").replace(/\/+$/, "")

    property var stats: []
    property var chips: []
    property double lastTs: 0          // write-time epoch stamped by write_json.py
    property double now: Date.now()

    // The heartbeat keeps "ts" advancing every 5 minutes even when nothing
    // changes, so silence beyond staleSecs means the pipeline is dead.
    readonly property bool stale: lastTs === 0 || (now / 1000 - lastTs) > cfg.staleSecs

    property var pending: null
    property double pendingSince: 0

    // Sizes: px() scales a 1x design value by uiScale; fs() is px() for text, never under minTextSize.
    function px(n) { return Math.round(n * (cfg.uiScale > 0 ? cfg.uiScale : 1)) }
    function fs(n) { return Math.max(cfg.minTextSize || 0, px(n)) }

    // Crisp text: hinted glyphs on whole pixels and a hard 1 px shadow (no layer, no blur).
    component Txt: Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.family: root.cfg.fontFamily
        style: Text.Raised
        styleColor: root.cfg.shadowColor
    }

    // HA sends Rainmeter-style "r,g,b" (optionally ",a") strings.
    function rgb(s, fallback) {
        const p = String(s || "").split(",").map(Number)
        if (p.length < 3 || p.some(isNaN)) return fallback
        return Qt.rgba(p[0] / 255, p[1] / 255, p[2] / 255, p.length > 3 ? p[3] / 255 : 1)
    }

    function apply(d) {
        const sc = Math.min(4, parseInt(d.stat_count) || 0)
        const cc = Math.min(6, parseInt(d.chip_count) || 0)
        const s = [], c = []
        for (let i = 1; i <= sc; i++)
            s.push({ label: d["s" + i + "_label"] || "", value: d["s" + i + "_value"] || "",
                     color: rgb(d["s" + i + "_color"], "white") })
        for (let i = 1; i <= cc; i++)
            c.push({ name: d["c" + i + "_name"] || "", sub: d["c" + i + "_sub"] || "",
                     color: rgb(d["c" + i + "_color"], "white") })
        stats = s
        chips = c
        lastTs = parseInt(d.ts) || 0
    }

    function fetchNow() {
        if (!haUrl) return
        if (pending) {
            if (Date.now() - pendingSince < 10000) return
            pending.abort()
            pending = null
        }
        const xhr = new XMLHttpRequest()
        pending = xhr
        pendingSince = Date.now()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (pending === xhr) pending = null
            // On failure keep the last payload: its ageing "ts" trips the
            // stale notice, exactly like the Rainmeter skin.
            if (xhr.status === 200) {
                try { apply(JSON.parse(xhr.responseText)) } catch (e) {}
            }
        }
        xhr.open("GET", haUrl + "/local/statusboard.json?t=" + Date.now())
        xhr.send()
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = Date.now()
    }
    Timer {
        interval: Math.max(2, root.cfg.pollSeconds) * 1000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.fetchNow()
    }

    fullRepresentation: Item {
        id: stage
        Layout.preferredWidth: board.naturalWidth
        Layout.preferredHeight: board.naturalHeight
        Layout.minimumWidth: root.px(200)
        Layout.minimumHeight: root.px(120)

        readonly property color muted: root.cfg.mutedColor
        readonly property int pad: root.px(18)  // left/right padding inside the panel

        Item {
            id: board
            objectName: "board"
            // Sized to the content, never wider than panelWidth or the widget.
            readonly property real naturalWidth: Math.min(root.px(root.cfg.panelWidth), Math.ceil(content.implicitWidth) + 2 * stage.pad)
            readonly property real naturalHeight: Math.ceil(content.implicitHeight) + 2 * content.anchors.topMargin
            width: Math.min(stage.width, naturalWidth)
            height: naturalHeight
            y: 0
            x: root.cfg.position === 0 ? 0
             : root.cfg.position === 2 ? stage.width - width
             : Math.round((stage.width - width) / 2)
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // Frosted glass (Frost.qml) or the plain translucent panel.
            Frost {
                objectName: "frost"
                anchors.fill: parent
                visible: root.cfg.showPanel && root.cfg.frosted
                radius: root.px(root.cfg.radius)
                tint: root.cfg.frostTint
            }
            Rectangle {
                anchors.fill: parent
                visible: root.cfg.showPanel && !root.cfg.frosted
                radius: root.px(root.cfg.radius)
                color: root.cfg.panelColor
            }

            ColumnLayout {
                id: content
                objectName: "content"
                anchors.top: parent.top
                anchors.topMargin: root.px(9)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: stage.pad
                anchors.rightMargin: stage.pad
                spacing: root.px(3)

                // ---- clock ----
                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(new Date(root.now), root.cfg.clockFormat)
                    color: "white"
                    font.pixelSize: root.px(44)
                    font.weight: Font.Medium
                }
                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -root.px(7)
                    text: Qt.formatDate(new Date(root.now), root.cfg.dateFormat)
                    color: stage.muted
                    font.pixelSize: root.fs(15)
                    font.weight: Font.Medium
                }

                // Divider, only with a panel (as in the original).
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: root.px(3)
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                    visible: root.cfg.showPanel && (root.stale || root.stats.length > 0 || root.chips.length > 0)
                }

                // ---- stale notice ----
                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.stale
                    text: root.lastTs === 0 ? i18n("WAITING FOR HOME ASSISTANT") : i18n("NO LINK - LIVE DATA PAUSED")
                    color: "#ff6e6e"
                    font.pixelSize: root.fs(13)
                    font.bold: true
                    font.letterSpacing: 1
                }

                // ---- stats: label over value ----
                // Rows and columns take their natural width (centred, no
                // stretching across empty space) and only shrink, eliding,
                // when the board is capped narrower than the content.
                RowLayout {
                    objectName: "statsRow"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.maximumWidth: implicitWidth
                    visible: !root.stale && root.stats.length > 0
                    spacing: root.px(18)
                    Repeater {
                        model: root.stats
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: implicitWidth
                            Layout.maximumWidth: implicitWidth
                            spacing: 0
                            Txt {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: modelData.label !== ""
                                text: modelData.label
                                color: stage.muted
                                elide: Text.ElideRight
                                font.pixelSize: root.fs(10)
                                font.bold: true
                            }
                            Txt {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.value
                                color: modelData.color
                                elide: Text.ElideRight
                                font.pixelSize: root.px(21)
                                font.weight: Font.Medium
                            }
                        }
                    }
                }

                // Second divider between the two rows, when both show.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: root.px(2)
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                    visible: root.cfg.showPanel && !root.stale && root.stats.length > 0 && root.chips.length > 0
                }

                // ---- chips: coloured name over sub-line ----
                RowLayout {
                    objectName: "chipsRow"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.maximumWidth: implicitWidth
                    visible: !root.stale && root.chips.length > 0
                    spacing: root.px(20)
                    Repeater {
                        model: root.chips
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: implicitWidth
                            Layout.maximumWidth: implicitWidth
                            spacing: -root.px(2)
                            Txt {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name
                                color: modelData.color
                                elide: Text.ElideRight
                                font.pixelSize: root.fs(14)
                                font.bold: true
                            }
                            Txt {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.sub
                                color: stage.muted
                                elide: Text.ElideRight
                                font.pixelSize: root.fs(11)
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
