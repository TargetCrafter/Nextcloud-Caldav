import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "../code/dateutils.js" as DateUtils

Item {
    id: fullRep

    property var agendaItems: []
    property bool isLoading: false
    property string lastError: ""
    property date lastUpdated
    property bool accountConfigured: false
    // [{ href, name, color, kinds }], for the add-item calendar pickers
    property var availableCalendars: []
    // Error from the last create attempt (distinct from lastError, which
    // governs the whole-list placeholder) - shown inline in the add bar.
    property string createError: ""
    property date currentTime

    // Month-calendar view (Appearance setting "viewMode"), fed from root's
    // own refreshMonth() - see main.qml.
    property var monthEvents: []
    property bool monthLoading: false
    property date monthCursor
    property date selectedDate: new Date()

    readonly property bool monthMode: plasmoid.configuration.viewMode === 1 /* Month */ &&
                                       plasmoid.configuration.displayMode !== 2 /* TasksOnly */
    readonly property var selectedDayEvents: computeSelectedDayEvents()

    onMonthCursorChanged: fullRep.selectedDate = new Date(fullRep.monthCursor)

    property bool showAddBar: false

    readonly property string addLockedType: {
        var mode = plasmoid.configuration.displayMode;
        if (mode === 1 /* EventsOnly */) return "event";
        if (mode === 2 /* TasksOnly */) return "task";
        return "";
    }

    signal refreshRequested()
    signal toggleTask(var task)
    signal openConfigureRequested()
    signal createTaskRequested(string calendarHref, string summary, var due)
    signal createEventRequested(string calendarHref, string summary, var start, var end, bool allDay)
    signal monthNavigate(int delta)

    function computeSelectedDayEvents() {
        var list = fullRep.monthEvents.filter(function (e) {
            return e.dtstart && DateUtils.isSameDay(e.dtstart, fullRep.selectedDate);
        });
        list.sort(function (a, b) {
            if (a.allDay !== b.allDay) return a.allDay ? -1 : 1;
            return a.dtstart.getTime() - b.dtstart.getTime();
        });
        return list;
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.preferredHeight: Kirigami.Units.gridUnit * 32

    readonly property bool showPlaceholder: lastError !== "" || (agendaItems.length === 0 && !isLoading)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 2
                text: i18n("Agenda")
                Layout.fillWidth: true
            }

            PlasmaComponents3.BusyIndicator {
                running: fullRep.isLoading
                visible: running
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
            }

            PlasmaComponents3.ToolButton {
                icon.name: "list-add"
                checked: fullRep.showAddBar
                checkable: true
                onClicked: fullRep.showAddBar = !fullRep.showAddBar
                PlasmaComponents3.ToolTip.text: i18n("Add event or task…")
                PlasmaComponents3.ToolTip.visible: hovered
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: fullRep.refreshRequested()
                PlasmaComponents3.ToolTip.text: i18n("Refresh")
                PlasmaComponents3.ToolTip.visible: hovered
            }

            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                onClicked: fullRep.openConfigureRequested()
                PlasmaComponents3.ToolTip.text: i18n("Configure…")
                PlasmaComponents3.ToolTip.visible: hovered
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        AddItemBar {
            visible: fullRep.showAddBar
            calendars: fullRep.availableCalendars
            lockedType: fullRep.addLockedType
            externalError: fullRep.createError
            onCreateTask: fullRep.createTaskRequested(calendarHref, summary, due)
            onCreateEvent: fullRep.createEventRequested(calendarHref, summary, start, end, allDay)
        }

        Kirigami.Separator { Layout.fillWidth: true; visible: fullRep.showAddBar }

        PlasmaExtras.PlaceholderMessage {
            Layout.alignment: Qt.AlignCenter
            Layout.fillWidth: true
            Layout.maximumWidth: parent.width - Kirigami.Units.gridUnit * 4
            Layout.topMargin: Kirigami.Units.gridUnit * 3
            visible: !fullRep.monthMode && fullRep.showPlaceholder
            iconName: fullRep.placeholderIcon()
            text: fullRep.placeholderTitle()
            explanation: fullRep.placeholderExplanation()
            helpfulAction: fullRep.lastError === "unconfigured" || fullRep.lastError === "nocalendars"
                           ? configureAction : refreshAction
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !fullRep.monthMode && !fullRep.showPlaceholder
            clip: true

            ListView {
                id: agendaList
                model: fullRep.agendaItems
                spacing: Kirigami.Units.smallSpacing
                boundsBehavior: Flickable.StopAtBounds

                delegate: Loader {
                    width: agendaList.width
                    sourceComponent: {
                        switch (modelData.type) {
                        case "dayHeader": return dayHeaderComponent;
                        case "sectionHeader": return dayHeaderComponent;
                        case "event": return eventComponent;
                        case "task": return taskComponent;
                        default: return null;
                        }
                    }
                    property var itemData: modelData
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: fullRep.monthMode
            spacing: 0

            MonthView {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                monthEvents: fullRep.monthEvents
                monthLoading: fullRep.monthLoading
                monthCursor: fullRep.monthCursor
                selectedDate: fullRep.selectedDate
                currentTime: fullRep.currentTime
                onNavigate: fullRep.monthNavigate(delta)
                onDaySelected: fullRep.selectedDate = day
            }

            Kirigami.Separator { Layout.fillWidth: true }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                font.bold: true
                text: Qt.formatDate(fullRep.selectedDate, "dddd · d MMMM")
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        visible: fullRep.selectedDayEvents.length === 0
                        opacity: 0.6
                        text: i18n("No events this day.")
                    }

                    Repeater {
                        model: fullRep.selectedDayEvents
                        delegate: EventDelegate {
                            Layout.fillWidth: true
                            eventData: modelData
                            currentTime: fullRep.currentTime
                        }
                    }
                }
            }
        }
    }

    Kirigami.Action {
        id: configureAction
        text: i18n("Set up account…")
        icon.name: "configure"
        onTriggered: fullRep.openConfigureRequested()
    }

    Kirigami.Action {
        id: refreshAction
        text: i18n("Try again")
        icon.name: "view-refresh"
        onTriggered: fullRep.refreshRequested()
    }

    Component {
        id: dayHeaderComponent
        DayHeader {
            date: parent.itemData.type === "dayHeader" ? parent.itemData.date : new Date()
            label: parent.itemData.type === "sectionHeader" ? parent.itemData.label : ""
            count: parent.itemData.count || 0
        }
    }

    Component {
        id: eventComponent
        EventDelegate {
            eventData: parent.itemData.data
            currentTime: fullRep.currentTime
        }
    }

    Component {
        id: taskComponent
        TaskDelegate {
            taskData: parent.itemData.data
            onToggled: fullRep.toggleTask(parent.itemData.data)
        }
    }

    function placeholderIcon() {
        if (lastError === "unconfigured" || lastError === "nocalendars") return "cloud";
        if (lastError !== "") return "dialog-warning";
        return "view-calendar";
    }

    function placeholderTitle() {
        switch (lastError) {
        case "unconfigured": return i18n("Connect your Nextcloud account");
        case "nocalendars": return i18n("No calendars selected");
        case "auth": return i18n("Sign-in failed");
        case "network": return i18n("Can't reach the server");
        case "notfound": return i18n("Server address not found");
        case "parse": return i18n("Couldn't read calendar data");
        case "timeout": return i18n("Timed out waiting for the server");
        case "": return i18n("Nothing coming up");
        default: return i18n("Something went wrong");
        }
    }

    function placeholderExplanation() {
        switch (lastError) {
        case "unconfigured": return i18n("Add your server address, username and an app password in the widget settings.");
        case "nocalendars": return i18n("Open settings and pick at least one calendar or task list to display.");
        case "auth": return i18n("Check your username and app password in the widget settings.");
        case "network": return i18n("Check the server address and your network connection.");
        case "notfound": return i18n("Double-check the Nextcloud server address in the widget settings.");
        case "parse": return i18n("The server returned data this widget doesn't understand.");
        case "timeout": return i18n("The server took too long to respond. Try refreshing again.");
        case "": return i18n("No events or tasks in the selected time range.");
        default: return "";
        }
    }
}
