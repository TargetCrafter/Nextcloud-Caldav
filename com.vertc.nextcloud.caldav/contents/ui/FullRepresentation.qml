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
    property date currentTime

    // Month/Week/WorkWeek calendar-grid view (Appearance setting
    // "viewMode"), fed from root's own refreshMonth() - see main.qml. The
    // property names are unchanged from when this was Month-only, but the
    // "month" they describe is a week's worth of days in Week/WorkWeek mode.
    property var monthEvents: []
    property bool monthLoading: false
    property date monthCursor
    property date selectedDate: new Date()

    readonly property int viewMode: plasmoid.configuration.viewMode
    readonly property bool weekMode: viewMode === 2 /* Week */ || viewMode === 3 /* WorkWeek */
    readonly property bool monthMode: (viewMode === 1 /* Month */ || weekMode) &&
                                       plasmoid.configuration.displayMode !== 2 /* TasksOnly */
    readonly property var selectedDayEvents: computeSelectedDayEvents()
    // The next day after selectedDate (within the currently loaded month -
    // see main.qml's refreshMonth) that has at least one event, so the day
    // detail panel can point at what's coming up even when that's not
    // "tomorrow" or even later in this same month. null if the rest of the
    // loaded month has nothing.
    readonly property var nextEventDay: computeNextEventDay()

    // Only jump the selected day when navigating to a period that no
    // longer contains it (not unconditionally on every monthCursor change,
    // which clobbered the "today" default back to the 1st/the week's start
    // as soon as monthCursor got its very first value from root at
    // construction time).
    onMonthCursorChanged: {
        var stillShown;
        if (fullRep.weekMode) {
            var weekStart = DateUtils.startOfWeek(fullRep.monthCursor);
            var weekEnd = DateUtils.addDays(weekStart, 6);
            stillShown = fullRep.selectedDate.getTime() >= weekStart.getTime() &&
                         fullRep.selectedDate.getTime() <= weekEnd.getTime();
        } else {
            stillShown = fullRep.selectedDate.getFullYear() === fullRep.monthCursor.getFullYear() &&
                         fullRep.selectedDate.getMonth() === fullRep.monthCursor.getMonth();
        }
        if (!stillShown) fullRep.selectedDate = new Date(fullRep.monthCursor);
    }

    readonly property string addLockedType: {
        var mode = plasmoid.configuration.displayMode;
        if (mode === 1 /* EventsOnly */) return "event";
        if (mode === 2 /* TasksOnly */) return "task";
        return "";
    }

    // Error from the last create/edit/delete attempt, and a counter root
    // bumps once one actually completes - root has no direct way to call a
    // function on the item form popup, only react through bound properties
    // (see main.qml's itemActionToken comment), which is what closes the
    // popup on success.
    property string formError: ""
    property int itemActionToken: 0
    onItemActionTokenChanged: itemFormPopup.close()

    signal refreshRequested()
    signal toggleTask(var task)
    signal toggleTaskCollapseRequested(string uid)
    signal toggleRecentlyClosedRequested()
    signal openConfigureRequested()
    signal createTaskRequested(string calendarHref, string summary, var due, bool dueHasTime, string description, string location, string parentUid, int priority)
    signal createEventRequested(string calendarHref, string summary, var start, var end, bool allDay, string description, string location)
    signal editTaskRequested(var task, string summary, var due, bool dueHasTime, string description, string location, int priority, string status, int percentComplete)
    signal editEventRequested(var event, string summary, var start, var end, bool allDay, string description, string location)
    signal deleteTaskRequested(var task)
    signal deleteEventRequested(var event)
    signal monthNavigate(int delta)
    signal monthJump(date month)

    // Selects today's date and, if it's not in the month currently shown,
    // asks root to jump straight there - a plain navigate(delta) can't
    // express an arbitrary jump, only a relative one.
    function goToToday() {
        var today = new Date();
        fullRep.selectedDate = today;
        fullRep.monthJump(today);
    }

    function headerTitle() {
        var mode = plasmoid.configuration.displayMode;
        if (mode === 2 /* TasksOnly */) return i18n("Tasks");
        var isCalendar = fullRep.viewMode === 1 /* Month */ || fullRep.weekMode;
        if (mode === 1 /* EventsOnly */) return isCalendar ? i18n("Calendar") : i18n("Agenda");
        return isCalendar ? i18n("Calendar + Tasks") : i18n("Agenda + Tasks");
    }

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

    // Returns { date, events } for the earliest day strictly after
    // selectedDate that has an event, or null if there isn't one in
    // monthEvents (which only covers the currently displayed period - the
    // visible grid in Month mode, which pads a few days into the
    // previous/next month, or the one week in Week/WorkWeek mode - this
    // deliberately doesn't reach any further into a following month's
    // data that hasn't been fetched).
    function computeNextEventDay() {
        var after = DateUtils.startOfDay(fullRep.selectedDate);
        after.setDate(after.getDate() + 1);
        var candidates = fullRep.monthEvents.filter(function (e) {
            return e.dtstart && e.dtstart.getTime() >= after.getTime();
        });
        if (candidates.length === 0) return null;
        candidates.sort(function (a, b) { return a.dtstart.getTime() - b.dtstart.getTime(); });
        var day = DateUtils.startOfDay(candidates[0].dtstart);
        var sameDay = candidates.filter(function (e) { return DateUtils.isSameDay(e.dtstart, day); });
        sameDay.sort(function (a, b) {
            if (a.allDay !== b.allDay) return a.allDay ? -1 : 1;
            return a.dtstart.getTime() - b.dtstart.getTime();
        });
        return { date: day, events: sameDay };
    }

    // "Today"/"Tomorrow"/"This Saturday" read faster than a full date for
    // the next-event hint below, but only stay unambiguous through the end
    // of the current week (Sunday-Saturday, matching MonthView's own week
    // layout) - "This Monday" for a date eight days out could mean either
    // this coming Monday or next week's, so that falls back to a full date.
    function formatNextEventDate(date) {
        var now = fullRep.currentTime;
        var offset = DateUtils.dayOffset(date, now);
        if (offset === 0) return i18n("Today");
        if (offset === 1) return i18n("Tomorrow");
        if (offset > 1) {
            var weekStart = DateUtils.startOfDay(now);
            weekStart.setDate(weekStart.getDate() - weekStart.getDay());
            var weekEnd = DateUtils.addDays(weekStart, 6);
            if (date.getTime() <= weekEnd.getTime()) {
                return i18n("This %1", Qt.formatDate(date, "dddd"));
            }
        }
        return Qt.formatDate(date, "d MMMM");
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
                text: fullRep.headerTitle()
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
                onClicked: itemFormPopup.openForCreate()
                PlasmaComponents3.ToolTip.text: {
                    if (fullRep.addLockedType === "event") return i18n("Add event…");
                    if (fullRep.addLockedType === "task") return i18n("Add task…");
                    return i18n("Add event or task…");
                }
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
                        case "recentlyClosedHeader": return dayHeaderComponent;
                        case "event": return eventComponent;
                        case "taskFamily": return taskFamilyComponent;
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
                viewMode: fullRep.viewMode
                monthEvents: fullRep.monthEvents
                monthLoading: fullRep.monthLoading
                monthCursor: fullRep.monthCursor
                selectedDate: fullRep.selectedDate
                currentTime: fullRep.currentTime
                onNavigate: fullRep.monthNavigate(delta)
                onDaySelected: fullRep.selectedDate = day
                onTodayRequested: fullRep.goToToday()
            }

            Kirigami.Separator { Layout.fillWidth: true }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                font.bold: true
                text: Qt.formatDate(fullRep.selectedDate, "dddd · d MMMM")
            }

            PlasmaComponents3.Label {
                // Points at what's actually coming up next, even when
                // that's several empty days away rather than tomorrow -
                // see computeNextEventDay's comment.
                visible: fullRep.nextEventDay !== null
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                opacity: 0.7
                elide: Text.ElideRight
                // Renders a server-supplied event summary - see
                // EventDelegate.qml's summary Label for why this must stay
                // plain text.
                textFormat: Text.PlainText
                text: fullRep.nextEventDay
                      ? i18n("Next: %1 · %2", fullRep.formatNextEventDate(fullRep.nextEventDay.date),
                             fullRep.nextEventDay.events[0].summary || i18n("(No title)"))
                      : ""

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fullRep.selectedDate = fullRep.nextEventDay.date
                }
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Kept always mounted/visible (rather than toggled by
                // selectedDayEvents.length) and using the exact same
                // Loader+Component delegate shape as the agenda list's
                // eventComponent above - the previous attempt set width
                // directly on EventDelegate and toggled the ScrollView's
                // own visibility right when a day was selected, and still
                // rendered empty.
                ListView {
                    id: dayEventsList
                    model: fullRep.selectedDayEvents
                    spacing: Kirigami.Units.smallSpacing
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Loader {
                        width: dayEventsList.width
                        sourceComponent: dayEventComponent
                        property var itemData: modelData
                    }

                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        visible: dayEventsList.count === 0
                        opacity: 0.6
                        text: i18n("No events this day.")
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
            label: parent.itemData.type === "sectionHeader" || parent.itemData.type === "recentlyClosedHeader"
                   ? parent.itemData.label : ""
            count: parent.itemData.count || 0
            expandable: parent.itemData.type === "recentlyClosedHeader"
            expanded: !!parent.itemData.expanded
            onToggleRequested: fullRep.toggleRecentlyClosedRequested()
        }
    }

    Component {
        id: eventComponent
        EventDelegate {
            eventData: parent.itemData.data
            currentTime: fullRep.currentTime
            onEditRequested: itemFormPopup.openForEdit(parent.itemData.data, false)
        }
    }

    // Same shape as eventComponent above, but for the month view's
    // day-detail panel, whose model is plain event objects rather than
    // agendaItems' {type, data} wrapper.
    Component {
        id: dayEventComponent
        EventDelegate {
            eventData: parent.itemData
            currentTime: fullRep.currentTime
            onEditRequested: itemFormPopup.openForEdit(parent.itemData, false)
        }
    }

    Component {
        id: taskFamilyComponent
        TaskFamilyCard {
            root: parent.itemData.root
            rows: parent.itemData.rows || []
            showCompletedDate: !!parent.itemData.showCompletedDate
            onToggled: (task) => fullRep.toggleTask(task)
            onEditRequested: (task) => itemFormPopup.openForEdit(task, true)
            onAddSubtaskRequested: (task) => itemFormPopup.openForCreate(task)
            onToggleCollapseRequested: (uid) => fullRep.toggleTaskCollapseRequested(uid)
        }
    }

    ItemFormPopup {
        id: itemFormPopup
        parent: fullRep
        calendars: fullRep.availableCalendars
        lockedType: fullRep.addLockedType
        defaultDate: fullRep.selectedDate
        externalError: fullRep.formError
        onCreateTask: fullRep.createTaskRequested(calendarHref, summary, due, dueHasTime, description, location, parentUid, priority)
        onCreateEvent: fullRep.createEventRequested(calendarHref, summary, start, end, allDay, description, location)
        onSaveTask: fullRep.editTaskRequested(task, summary, due, dueHasTime, description, location, priority, status, percentComplete)
        onSaveEvent: fullRep.editEventRequested(event, summary, start, end, allDay, description, location)
        onRemoveItem: {
            if (isTask) fullRep.deleteTaskRequested(item);
            else fullRep.deleteEventRequested(item);
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
