import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_displayMode: displayModeCombo.currentIndex
    property alias cfg_daysAhead: daysAheadSpin.value
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_showTasks: showTasksCheck.checked
    property alias cfg_showCompletedTasks: showCompletedCheck.checked
    property alias cfg_viewMode: viewModeCombo.currentIndex
    property alias cfg_compactMode: compactModeCombo.currentIndex
    property alias cfg_showEventLocation: showLocationCheck.checked
    property alias cfg_use24HourClock: use24HourCheck.checked
    property alias cfg_notifyEventAlarms: notifyEventAlarmsCheck.checked
    property alias cfg_notifyTasksDueSoon: notifyTasksDueSoonCheck.checked
    property alias cfg_taskDueSoonMinutes: taskDueSoonSpin.value

    QQC2.ComboBox {
        id: displayModeCombo
        Kirigami.FormData.label: i18n("Show:")
        model: [i18n("Events and tasks"), i18n("Events only"), i18n("Tasks only")]
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.75
        text: i18n("Add a second copy of this widget to show events and tasks side by side, each set to a different option here.")
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

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
        visible: displayModeCombo.currentIndex === 0
    }

    QQC2.CheckBox {
        id: showCompletedCheck
        visible: displayModeCombo.currentIndex !== 1
        enabled: displayModeCombo.currentIndex === 2 || showTasksCheck.checked
        text: i18n("Include completed tasks")
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        id: viewModeCombo
        Kirigami.FormData.label: i18n("Layout:")
        model: [i18n("Agenda list"), i18n("Month calendar")]
        enabled: displayModeCombo.currentIndex !== 2
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: displayModeCombo.currentIndex === 2
        opacity: 0.7
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        text: i18n("Month view isn't available in Tasks only mode.")
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

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: notifyEventAlarmsCheck
        Kirigami.FormData.label: i18n("Notifications:")
        text: i18n("Notify for event reminders")
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: notifyEventAlarmsCheck.checked
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.75
        text: i18n("Uses the reminder time already set on the event (e.g. in Nextcloud Calendar) - this doesn't add its own separate reminder.")
    }

    QQC2.CheckBox {
        id: notifyTasksDueSoonCheck
        text: i18n("Notify when a task is due soon")
    }

    QQC2.SpinBox {
        id: taskDueSoonSpin
        Kirigami.FormData.label: i18n("Notify:")
        enabled: notifyTasksDueSoonCheck.checked
        from: 1
        to: 1440
        textFromValue: (value) => i18np("%1 minute before due", "%1 minutes before due", value)
        valueFromText: (text) => parseInt(text, 10) || 1
    }
}
