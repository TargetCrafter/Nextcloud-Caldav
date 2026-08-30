import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_daysAhead: daysAheadSpin.value
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_showTasks: showTasksCheck.checked
    property alias cfg_showCompletedTasks: showCompletedCheck.checked
    property alias cfg_compactMode: compactModeCombo.currentIndex
    property alias cfg_showEventLocation: showLocationCheck.checked
    property alias cfg_use24HourClock: use24HourCheck.checked

    QQC2.SpinBox {
        id: daysAheadSpin
        Kirigami.FormData.label: i18n("Show events up to:")
        from: 1
        to: 90
        textFromValue: (value) => i18np("%1 day ahead", "%1 days ahead", value)
        valueFromText: (text) => parseInt(text, 10) || 1
    }

    QQC2.SpinBox {
        id: refreshSpin
        Kirigami.FormData.label: i18n("Refresh every:")
        from: 1
        to: 240
        textFromValue: (value) => i18np("%1 minute", "%1 minutes", value)
        valueFromText: (text) => parseInt(text, 10) || 1
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showTasksCheck
        Kirigami.FormData.label: i18n("Tasks:")
        text: i18n("Show tasks (to-dos)")
    }

    QQC2.CheckBox {
        id: showCompletedCheck
        enabled: showTasksCheck.checked
        text: i18n("Include completed tasks")
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        id: compactModeCombo
        Kirigami.FormData.label: i18n("Panel shows:")
        model: [i18n("Next event"), i18n("Today's event count"), i18n("Icon only")]
    }

    QQC2.CheckBox {
        id: showLocationCheck
        Kirigami.FormData.label: i18n("Events:")
        text: i18n("Show event location")
    }

    QQC2.CheckBox {
        id: use24HourCheck
        text: i18n("Use 24-hour time")
    }
}
