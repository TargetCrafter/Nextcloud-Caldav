import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

Item {
    id: fullRep

    property var agendaItems: []
    property bool isLoading: false
    property string lastError: ""
    property date lastUpdated
    property bool accountConfigured: false

    signal refreshRequested()
    signal toggleTask(var task)
    signal openConfigureRequested()

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

        PlasmaExtras.PlaceholderMessage {
            Layout.alignment: Qt.AlignCenter
            Layout.fillWidth: true
            Layout.maximumWidth: parent.width - Kirigami.Units.gridUnit * 4
            Layout.topMargin: Kirigami.Units.gridUnit * 3
            visible: fullRep.showPlaceholder
            iconName: fullRep.placeholderIcon()
            text: fullRep.placeholderTitle()
            explanation: fullRep.placeholderExplanation()
            helpfulAction: fullRep.lastError === "unconfigured" || fullRep.lastError === "nocalendars"
                           ? configureAction : refreshAction
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !fullRep.showPlaceholder
            clip: true

            ListView {
                id: agendaList
                model: fullRep.agendaItems
                spacing: 0
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
        case "": return i18n("No events or tasks in the selected time range.");
        default: return "";
        }
    }
}
