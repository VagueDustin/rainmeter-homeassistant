/*
 * HA Now Playing - KDE Plasma 6 port of the Rainmeter skin from
 * https://github.com/VagueDustin/rainmeter-homeassistant (MIT).
 *
 * Reads the same unauthenticated /local/nowplaying.json the Home Assistant
 * package already writes, so nothing on the HA side changes and no access
 * token is stored on this machine.
 *
 * Title, artist and source are each at most maxTextWidth wide; a line that
 * doesn't fit holds, then scrolls (Marquee.qml). The panel is frosted glass
 * (Frost.qml) unless that's turned off.
 *
 * Sharpness: sizes go through px() (uiScale) and fs() (never under
 * minTextSize), and the text is hinted with a hard 1 px shadow (Marquee.qml)
 * instead of a blurred layer effect.
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
    // The cover's second colour (hex2 in the feed) for the source line; the accent when there is none.
    readonly property color accent2: np && np.hex2 ? np.hex2 : accent
    readonly property bool hasArt: np !== null && np.art === "ok" && (np.cover_url || "") !== ""

    property var pending: null
    property double pendingSince: 0

    // Sizes: px() scales a 1x design value by uiScale; fs() is px() for text, never under minTextSize.
    function px(n) { return Math.round(n * (cfg.uiScale > 0 ? cfg.uiScale : 1)) }
    function fs(n) { return Math.max(cfg.minTextSize || 0, px(n)) }
    readonly property int artPx: px(cfg.artSize)

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
        Layout.preferredWidth: root.px(900)
        Layout.preferredHeight: root.artPx
        Layout.minimumWidth: root.px(root.cfg.minWidth)
        Layout.minimumHeight: root.px(64)

        readonly property int textX: panel.height + root.px(20)
        readonly property int padR: root.px(20)
        // The panel grows rightward to fit the longest line, capped at
        // maxTextWidth (longer lines scroll), from minWidth up to the widget's
        // own width.
        readonly property real wanted: textX + Math.min(root.px(root.cfg.maxTextWidth),
                                                        Math.max(title.naturalWidth, artist.naturalWidth,
                                                                 source.visible ? source.naturalWidth : 0)) + padR

        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Item {
            id: panel
            objectName: "panel"
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            // bottomOffset lifts the panel off the widget's bottom edge: Plasma keeps desktop
            // widgets on a 16 px grid, so an exact screen margin can need a few px here.
            anchors.bottomMargin: root.cfg.bottomOffset
            height: Math.min(parent.height - root.cfg.bottomOffset, root.artPx)
            width: Math.round(Math.min(parent.width, Math.max(root.px(root.cfg.minWidth), stage.wanted)))
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Frost {
                objectName: "frost"
                anchors.fill: parent
                visible: root.cfg.frosted
                radius: root.px(root.cfg.radius)
                tint: root.cfg.frostTint
            }
            Rectangle {
                anchors.fill: parent
                visible: !root.cfg.frosted
                radius: root.px(root.cfg.radius)
                color: root.cfg.panelColor
            }

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
                    Rectangle { anchors.fill: parent; radius: root.px(root.cfg.radius) }
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
                id: textBlock
                anchors.left: parent.left
                anchors.leftMargin: stage.textX
                anchors.right: parent.right
                anchors.rightMargin: stage.padR
                // Centred on a whole pixel, so no line straddles two pixel rows.
                y: Math.round((parent.height - implicitHeight) / 2)
                spacing: root.px(4)

                Marquee {
                    id: title
                    objectName: "title"
                    Layout.fillWidth: true
                    text: root.np ? (root.np.title || "") : ""
                    color: "white"
                    styleColor: root.cfg.shadowColor
                    speed: root.px(root.cfg.scrollSpeed)
                    font.family: root.cfg.fontFamily
                    font.hintingPreference: Font.PreferFullHinting
                    font.pixelSize: root.fs(root.cfg.titleSize)
                    font.weight: Font.Medium
                }
                Marquee {
                    id: artist
                    objectName: "artist"
                    Layout.fillWidth: true
                    text: root.np ? (root.np.artist || "") : ""
                    color: root.accent
                    styleColor: root.cfg.shadowColor
                    speed: root.px(root.cfg.scrollSpeed)
                    font.family: root.cfg.fontFamily
                    font.hintingPreference: Font.PreferFullHinting
                    font.pixelSize: root.fs(root.cfg.artistSize)
                    font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
                // Where it's playing from (AirPlay, Spotify, FateCast · <pc>, HDMI ...)
                Marquee {
                    id: source
                    objectName: "source"
                    Layout.fillWidth: true
                    visible: root.cfg.showSource && text !== ""
                    text: root.np ? (root.np.source || "") : ""
                    color: root.accent2
                    opacity: 0.85
                    styleColor: root.cfg.shadowColor
                    speed: root.px(root.cfg.scrollSpeed)
                    font.family: root.cfg.fontFamily
                    font.hintingPreference: Font.PreferFullHinting
                    font.pixelSize: root.fs(13)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.5
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
            }
        }
    }
}
