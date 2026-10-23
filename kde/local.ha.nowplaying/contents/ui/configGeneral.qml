import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property real cfg_uiScale: 1.0
    property alias cfg_minTextSize: minTextSize.value
    property alias cfg_haUrl: haUrl.text
    property alias cfg_pollSeconds: pollSeconds.value
    property alias cfg_showSource: showSource.checked
    property alias cfg_minWidth: minWidth.value
    property alias cfg_artSize: artSize.value
    property alias cfg_radius: radius.value
    property alias cfg_fontFamily: fontFamily.text
    property alias cfg_titleSize: titleSize.value
    property alias cfg_artistSize: artistSize.value
    property alias cfg_panelColor: panelColor.text
    property alias cfg_shadowColor: shadowColor.text
    property alias cfg_maxTextWidth: maxTextWidth.value
    property alias cfg_scrollSpeed: scrollSpeed.value
    property alias cfg_bottomOffset: bottomOffset.value
    property alias cfg_frosted: frosted.checked
    property alias cfg_frostTint: frostTint.text

    Kirigami.FormLayout {
        QQC2.TextField {
            id: haUrl
            Kirigami.FormData.label: i18n("Home Assistant URL:")
            placeholderText: "http://homeassistant.local:8123"
        }
        QQC2.SpinBox { id: pollSeconds; from: 1; to: 60; Kirigami.FormData.label: i18n("Check every (seconds):") }
        QQC2.CheckBox { id: showSource; text: i18n("Show which player it's coming from") }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Appearance") }
        QQC2.SpinBox {
            id: uiScalePct; from: 50; to: 300; stepSize: 5
            value: Math.round(cfg_uiScale * 100)
            onValueModified: cfg_uiScale = value / 100
            Kirigami.FormData.label: i18n("Scale (%):")
        }
        QQC2.SpinBox { id: minTextSize; from: 0; to: 48; Kirigami.FormData.label: i18n("Minimum text size (px):") }
        QQC2.Label {
            text: i18n("100% and 0 suit a desktop monitor. For a projector or TV seen from across a room, try 125% and 16 px.")
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
        QQC2.SpinBox { id: minWidth; from: 200; to: 2000; Kirigami.FormData.label: i18n("Minimum panel width:") }
        QQC2.SpinBox { id: maxTextWidth; from: 120; to: 2000; Kirigami.FormData.label: i18n("Maximum text width:") }
        QQC2.SpinBox { id: scrollSpeed; from: 10; to: 200; Kirigami.FormData.label: i18n("Scroll speed (px/s):") }
        QQC2.Label {
            text: i18n("Longer lines pause, then scroll.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
        QQC2.SpinBox { id: artSize; from: 64; to: 400; Kirigami.FormData.label: i18n("Artwork / panel height:") }
        QQC2.SpinBox { id: bottomOffset; from: 0; to: 64; Kirigami.FormData.label: i18n("Lift panel off the widget bottom (px):") }
        QQC2.SpinBox { id: radius; from: 0; to: 48; Kirigami.FormData.label: i18n("Corner radius:") }
        QQC2.TextField { id: fontFamily; Kirigami.FormData.label: i18n("Font:"); placeholderText: i18n("System default") }
        QQC2.SpinBox { id: titleSize; from: 8; to: 72; Kirigami.FormData.label: i18n("Title size (px):") }
        QQC2.SpinBox { id: artistSize; from: 8; to: 72; Kirigami.FormData.label: i18n("Artist size (px):") }
        QQC2.CheckBox { id: frosted; text: i18n("Frosted glass panel") }
        QQC2.TextField { id: frostTint; enabled: frosted.checked; Kirigami.FormData.label: i18n("Glass tint (#AARRGGBB):") }
        QQC2.TextField { id: panelColor; enabled: !frosted.checked; Kirigami.FormData.label: i18n("Panel colour (#AARRGGBB):") }
        QQC2.TextField { id: shadowColor; Kirigami.FormData.label: i18n("Text shadow (#AARRGGBB):") }
    }
}
