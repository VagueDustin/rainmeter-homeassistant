/*
 * HA Status Board - KDE Plasma 6 port of the Rainmeter skin from
 * https://github.com/VagueDustin/rainmeter-homeassistant (MIT).
 *
 * A clock with two rows underneath, both driven entirely by
 * /local/statusboard.json from the unchanged Home Assistant package:
 *   STATS  up to 4 slots, a label over a value
 *   CHIPS  up to 6 slots, a coloured name over a sub-line
 * Empty slots hide, empty rows collapse, and the panel height follows.
 * Time and date come from this machine, so the clock keeps ticking if HA
 * goes away.
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
        Layout.preferredWidth: root.cfg.panelWidth
        Layout.preferredHeight: 280
        Layout.minimumWidth: 300
        Layout.minimumHeight: 140

        readonly property color muted: root.cfg.mutedColor
        readonly property string family: root.cfg.fontFamily

        Item {
            id: board
            width: Math.min(stage.width, root.cfg.panelWidth)
            height: content.implicitHeight + 28
            y: 0
            x: root.cfg.position === 0 ? 0
             : root.cfg.position === 2 ? stage.width - width
             : (stage.width - width) / 2
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                visible: root.cfg.showPanel
                radius: root.cfg.radius
                color: root.cfg.panelColor
            }

            ColumnLayout {
                id: content
                anchors.top: parent.top
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 6

                // Soft halo shadow so text stays readable with or without the panel.
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.cfg.shadowColor
                    shadowBlur: 0.55
                    shadowScale: 1.02
                    shadowVerticalOffset: 2
                    shadowHorizontalOffset: 1
                }

                // ---- clock ----
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(new Date(root.now), root.cfg.clockFormat)
                    color: "white"
                    font.family: stage.family
                    font.pixelSize: 64
                    font.weight: Font.Light
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -10
                    text: Qt.formatDate(new Date(root.now), root.cfg.dateFormat)
                    color: stage.muted
                    font.family: stage.family
                    font.pixelSize: 19
                }

                // Divider, only with a panel (as in the original).
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                    visible: root.cfg.showPanel && (root.stale || root.stats.length > 0 || root.chips.length > 0)
                }

                // ---- stale notice ----
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.stale
                    text: root.lastTs === 0 ? i18n("WAITING FOR HOME ASSISTANT") : i18n("NO LINK - LIVE DATA PAUSED")
                    color: "#ff6e6e"
                    font.family: stage.family
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1
                }

                // ---- stats: label over value ----
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.stale && root.stats.length > 0
                    spacing: 0
                    Repeater {
                        model: root.stats
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1      // equal columns
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: modelData.label !== ""
                                text: modelData.label
                                color: stage.muted
                                elide: Text.ElideRight
                                font.family: stage.family
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.value
                                color: modelData.color
                                elide: Text.ElideRight
                                font.family: stage.family
                                font.pixelSize: 30
                            }
                        }
                    }
                }

                // ---- chips: coloured name over sub-line ----
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.stale && root.chips.length > 0
                    spacing: 0
                    Repeater {
                        model: root.chips
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: -2
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name
                                color: modelData.color
                                elide: Text.ElideRight
                                font.family: stage.family
                                font.pixelSize: 20
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.sub
                                color: stage.muted
                                elide: Text.ElideRight
                                font.family: stage.family
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }
    }
}
