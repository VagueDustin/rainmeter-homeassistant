import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_haUrl: haUrl.text
    property alias cfg_pollSeconds: pollSeconds.value
    property alias cfg_staleSecs: staleSecs.value
    property alias cfg_clockFormat: clockFormat.text
    property alias cfg_dateFormat: dateFormat.text
    property alias cfg_position: position.currentIndex
    property alias cfg_panelWidth: panelWidth.value
    property alias cfg_showPanel: showPanel.checked
    property alias cfg_radius: radius.value
    property alias cfg_fontFamily: fontFamily.text
    property alias cfg_panelColor: panelColor.text
    property alias cfg_mutedColor: mutedColor.text
    property alias cfg_shadowColor: shadowColor.text

    Kirigami.FormLayout {
        QQC2.TextField {
            id: haUrl
            Kirigami.FormData.label: i18n("Home Assistant URL:")
            placeholderText: "http://homeassistant.local:8123"
        }
        QQC2.SpinBox { id: pollSeconds; from: 2; to: 300; Kirigami.FormData.label: i18n("Check every (seconds):") }
        QQC2.SpinBox {
            id: staleSecs; from: 60; to: 86400; stepSize: 60
            Kirigami.FormData.label: i18n("Mark data stale after (seconds):")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Clock") }
        QQC2.TextField { id: clockFormat; Kirigami.FormData.label: i18n("Time format:") }
        QQC2.TextField { id: dateFormat; Kirigami.FormData.label: i18n("Date format:") }
        QQC2.Label {
            text: i18n("Uses Qt format codes, e.g. h:mm AP, HH:mm, dddd d MMMM.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Appearance") }
        QQC2.ComboBox {
            id: position
            Kirigami.FormData.label: i18n("Align board:")
            model: [i18n("Left"), i18n("Centre"), i18n("Right")]
        }
        QQC2.SpinBox { id: panelWidth; from: 300; to: 2000; Kirigami.FormData.label: i18n("Board width:") }
        QQC2.CheckBox { id: showPanel; text: i18n("Draw a panel behind the text") }
        QQC2.SpinBox { id: radius; from: 0; to: 48; Kirigami.FormData.label: i18n("Corner radius:") }
        QQC2.TextField { id: fontFamily; Kirigami.FormData.label: i18n("Font:"); placeholderText: i18n("System default") }
        QQC2.TextField { id: panelColor; Kirigami.FormData.label: i18n("Panel colour (#AARRGGBB):") }
        QQC2.TextField { id: mutedColor; Kirigami.FormData.label: i18n("Muted text colour:") }
        QQC2.TextField { id: shadowColor; Kirigami.FormData.label: i18n("Text shadow (#AARRGGBB):") }
    }
}
