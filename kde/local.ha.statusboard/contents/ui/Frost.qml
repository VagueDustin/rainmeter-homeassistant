/*
 * Liquid-glass panel background (shared by local.ha.statusboard and
 * local.ha.nowplaying; keep the two copies identical).
 *
 * A light, mostly clear pane: a faint white tint that lets the wallpaper's
 * colours through, a bright specular rim that is strongest along the top and
 * left edges and fades towards the bottom right, a soft inner glow and a
 * diffuse drop shadow. Text legibility comes from the text's own shadow, not
 * from darkening the pane.
 *
 * It does not blur the wallpaper. Desktop widgets share a scene with the
 * wallpaper, so KWin's blur can't reach them, and sampling the containment's
 * wallpaper item (ShaderEffectSource + MultiEffect blur) crash-looped
 * plasmashell (SIGABRT in the NVIDIA GL driver) under an animated wallpaper
 * plugin, so that route was dropped.
 */
import QtQuick
import QtQuick.Effects

Item {
    id: frost

    property real radius: 18
    // Fill of the pane; keep it light (white at 8-15%) for the glass look.
    property color tint: "#1fffffff"
    // 0..1: how bright the specular rim is (top-left end of the gradient).
    property real edge: 0.6

    RectangularShadow {
        anchors.fill: parent
        radius: frost.radius
        blur: 28
        offset.y: 6
        color: Qt.rgba(0, 0, 0, 0.22)
    }

    // The rim: a diagonal white gradient, seen as a 1.5 px border because the
    // pane below is inset by that much.
    Rectangle {
        id: rim
        anchors.fill: parent
        radius: frost.radius
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, frost.edge) }
            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, frost.edge * 0.35) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, frost.edge * 0.15) }
        }
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: paneMask
        }
    }

    // Mask that cuts the pane's area out of the rim, leaving only the edge.
    Item {
        id: paneMask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1.5
            radius: Math.max(0, frost.radius - 1.5)
            color: "black"
        }
    }

    // The pane: the light tint plus a sheen that is brighter at the top, as
    // light catching the upper surface of the glass.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1.5
        radius: Math.max(0, frost.radius - 1.5)
        color: frost.tint

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.04) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.02) }
            }
        }

        // Inner glow: a soft light line just inside the rim.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }
    }
}
