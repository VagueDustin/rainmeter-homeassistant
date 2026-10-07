/*
 * HA Now Playing - KDE Plasma 6 port of the Rainmeter skin from
 * https://github.com/VagueDustin/rainmeter-homeassistant (MIT).
 *
 * Reads the same unauthenticated /local/nowplaying.json the Home Assistant
 * package already writes, so nothing on the HA side changes and no access
 * token is stored on this machine.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property var cfg: Plasmoid.configuration
    readonly property string haUrl: (cfg.haUrl || "").replace(/\/+$/, "")

    property var np: null
    // Same rule as the skin: only visible while playing or paused.
    readonly property bool active: np !== null && (np.state === "playing" || np.state === "paused")
    readonly property color accent: np && np.hex ? np.hex : "#aab2be"
    readonly property bool hasArt: np !== null && np.art === "ok" && (np.cover_url || "") !== ""

    property var pending: null
    property double pendingSince: 0

    function fetchNow() {
        if (!haUrl) return
        // QML's XMLHttpRequest has no timeout property, so abandon stuck requests.
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
            if (xhr.status === 200) {
                try { np = JSON.parse(xhr.responseText); return } catch (e) {}
            }
            // A missing or unreachable file must not freeze the last track on
            // screen, so any failure means "nothing playing".
            np = null
        }
        xhr.open("GET", haUrl + "/local/nowplaying.json?t=" + Date.now())
        xhr.send()
    }

    Timer {
        interval: Math.max(1, root.cfg.pollSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchNow()
    }

    fullRepresentation: Item {
        id: stage
        Layout.preferredWidth: 900
        Layout.preferredHeight: root.cfg.artSize
        Layout.minimumWidth: root.cfg.minWidth
        Layout.minimumHeight: 64

        readonly property int textX: panel.height + 20
        readonly property int padR: 20
        // The panel grows rightward to fit the longer line, from minWidth up
        // to the widget's own width. Resize the widget to set the ceiling.
        readonly property real wanted: textX + Math.max(titleProbe.implicitWidth,
                                                        artistProbe.implicitWidth,
                                                        root.cfg.showSource ? sourceProbe.implicitWidth : 0) + padR

        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        // Unconstrained copies used only to measure natural text width.
        Text { id: titleProbe; visible: false; text: title.text; font: title.font }
        Text { id: artistProbe; visible: false; text: artist.text; font: artist.font }
        Text { id: sourceProbe; visible: false; text: source.text; font: source.font }

        Rectangle {
            id: panel
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: Math.min(parent.height, root.cfg.artSize)
            width: Math.min(parent.width, Math.max(root.cfg.minWidth, stage.wanted))
            radius: root.cfg.radius
            color: root.cfg.panelColor
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // ---- artwork, rounded on the left to match the panel ----
            Item {
                id: artBox
                width: panel.height
                height: panel.height

                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.hasArt ? root.np.cover_url : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: false
                    layer.enabled: true
                }
                Rectangle {
                    id: placeholder
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.darker(root.accent, 2.2) }
                        GradientStop { position: 1; color: Qt.darker(root.accent, 1.2) }
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.4
                        height: width
                        source: "audio-x-generic"
                        color: "white"
                        isMask: true
                    }
                }
                Item {
                    id: artMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: root.cfg.radius }
                    Rectangle { anchors.right: parent.right; width: parent.width / 2; height: parent.height }
                }
                MultiEffect {
                    anchors.fill: parent
                    source: (root.hasArt && cover.status === Image.Ready) ? cover : placeholder
                    maskEnabled: true
                    maskSource: artMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }

            // ---- text block ----
            ColumnLayout {
                anchors.left: parent.left
                anchors.leftMargin: stage.textX
                anchors.right: parent.right
                anchors.rightMargin: stage.padR
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.cfg.shadowColor
                    shadowBlur: 0.4
                    shadowVerticalOffset: 1
                    shadowHorizontalOffset: 1
                }

                Text {
                    id: title
                    Layout.fillWidth: true
                    text: root.np ? (root.np.title || "") : ""
                    color: "white"
                    elide: Text.ElideRight
                    font.family: root.cfg.fontFamily
                    font.pixelSize: root.cfg.titleSize
                }
                Text {
                    id: artist
                    Layout.fillWidth: true
                    text: root.np ? (root.np.artist || "") : ""
                    color: root.accent
                    elide: Text.ElideRight
                    font.family: root.cfg.fontFamily
                    font.pixelSize: root.cfg.artistSize
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
                Text {
                    id: source
                    Layout.fillWidth: true
                    visible: root.cfg.showSource && text !== ""
                    text: root.np ? (root.np.source || "") : ""
                    color: "#bec4cd"
                    elide: Text.ElideRight
                    font.family: root.cfg.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }
}
