import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Floating add/edit form for a single event or task, replacing what used
// to be two separate inline panels (AddItemBar/EditItemBar) that pushed
// down and competed for space with the agenda list underneath. One popup
// handles both modes since the field set (title, calendar, due/start,
// description, location) is otherwise identical between them - only the
// calendar picker and type tabs are create-only, since an existing item's
// kind and calendar aren't editable here.
QQC2.Popup {
    id: popup

    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    width: parent ? Math.min(Kirigami.Units.gridUnit * 22, parent.width - Kirigami.Units.gridUnit * 2) : Kirigami.Units.gridUnit * 22

    background: Rectangle {
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Kirigami.Theme.highlightColor
    }

    property bool editMode: false
    property var editingItem: null
    property bool isTask: true
    // "task"/"event"/"" - forces the create-mode type when the widget is
    // restricted to a single display mode (see main.xml's displayMode), so
    // there's nothing to switch between and the tab row is just noise.
    property string lockedType: ""

    // [{ href, name, color, kinds }]
    property var calendars: []
    property string externalError: ""
    // Prefilled start/due date for a new item: the day selected in the
    // month-calendar view, or today otherwise.
    property date defaultDate: new Date()

    signal createTask(string calendarHref, string summary, var due, string description, string location)
    signal createEvent(string calendarHref, string summary, var start, var end, bool allDay, string description, string location)
    signal saveTask(var task, string summary, var due, string description, string location)
    signal saveEvent(var event, string summary, var start, var end, bool allDay, string description, string location)
    signal removeItem(var item, bool isTask)

    readonly property var taskCalendars: calendars.filter(function (c) { return c.kinds.indexOf("VTODO") !== -1; })
    readonly property var eventCalendars: calendars.filter(function (c) { return c.kinds.indexOf("VEVENT") !== -1; })
    readonly property var activeCalendars: isTask ? taskCalendars : eventCalendars

    // Day/month order taken from the system locale, so typed dates read
    // the way this user expects (e.g. DD-MM-YYYY) rather than a hardcoded
    // ISO-style YYYY-MM-DD. Always a 4-digit year with "-" separators
    // regardless of locale, since the locale's own short-date pattern can
    // use 2-digit years or different separators a small hand-rolled parser
    // can't reliably round-trip.
    readonly property bool dayFirst: popup.detectDayFirst()
    readonly property string dateHint: dayFirst ? "DD-MM-YYYY" : "MM-DD-YYYY"

    function detectDayFirst() {
        try {
            var fmt = Qt.locale().dateFormat(Locale.ShortFormat).toLowerCase();
            var di = fmt.indexOf("d");
            var mi = fmt.indexOf("m");
            if (di === -1 || mi === -1) return true;
            return di < mi;
        } catch (e) {
            return true;
        }
    }

    function openForCreate() {
        popup.editMode = false;
        popup.editingItem = null;
        localError = "";
        confirmingDelete = false;
        confirmTimer.stop();
        if (popup.lockedType === "task") popup.isTask = true;
        else if (popup.lockedType === "event") popup.isTask = false;
        titleField.text = "";
        var text = popup.formatDateField(popup.defaultDate);
        dueField.text = "";
        startDateField.text = text;
        startTimeField.text = "";
        allDayCheck.checked = false;
        durationSpin.value = 1;
        descriptionField.text = "";
        locationField.text = "";
        popup.open();
    }

    function openForEdit(item, taskFlag) {
        popup.editMode = true;
        popup.editingItem = item;
        popup.isTask = taskFlag;
        localError = "";
        confirmingDelete = false;
        confirmTimer.stop();
        titleField.text = item.summary || "";
        descriptionField.text = item.description || "";
        locationField.text = item.location || "";
        if (taskFlag) {
            dueField.text = item.due ? popup.formatDateField(item.due) : "";
        } else {
            allDayCheck.checked = !!item.allDay;
            startDateField.text = item.dtstart ? popup.formatDateField(item.dtstart) : "";
            startTimeField.text = (item.dtstart && !item.allDay) ? popup.formatTimeField(item.dtstart) : "";
            var durationHours = (item.dtstart && item.dtend) ? Math.max(1, Math.round((item.dtend.getTime() - item.dtstart.getTime()) / 3600000)) : 1;
            durationSpin.value = durationHours;
        }
        popup.open();
    }

    property string localError: ""
    property bool confirmingDelete: false

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: popup.confirmingDelete = false
    }

    ColumnLayout {
        width: popup.availableWidth
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                font.bold: true
                text: {
                    if (popup.editMode) return popup.isTask ? i18n("Edit task") : i18n("Edit event");
                    return popup.isTask ? i18n("New task") : i18n("New event");
                }
            }

            QQC2.Button {
                text: i18n("Close")
                flat: true
                onClicked: popup.close()
            }
        }

        PlasmaComponents3.TabBar {
            id: typeBar
            visible: !popup.editMode && popup.lockedType === ""
            Layout.fillWidth: false
            // TabBar splits its own width evenly between tabs; left to its
            // implicit width it ends up too narrow for "Event", wrapping
            // the text mid-word. A fixed, generous preferred width avoids
            // that without stretching across the whole bar.
            Layout.preferredWidth: Kirigami.Units.gridUnit * 9
            currentIndex: popup.isTask ? 0 : 1
            onCurrentIndexChanged: popup.isTask = currentIndex === 0

            PlasmaComponents3.TabButton { text: i18n("Task") }
            PlasmaComponents3.TabButton { text: i18n("Event") }
        }

        QQC2.TextField {
            id: titleField
            Layout.fillWidth: true
            placeholderText: popup.isTask ? i18n("Task title") : i18n("Event title")
        }

        QQC2.ComboBox {
            id: calendarCombo
            Layout.fillWidth: true
            visible: !popup.editMode
            model: popup.activeCalendars.map(function (c) { return c.name; })
            enabled: popup.activeCalendars.length > 0
        }

        RowLayout {
            Layout.fillWidth: true
            visible: popup.isTask
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("Due:") }
            QQC2.TextField {
                id: dueField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                placeholderText: popup.dateHint + i18n(" (optional)")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !popup.isTask
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                id: allDayCheck
                text: i18n("All day")
            }
            QQC2.TextField {
                id: startDateField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                placeholderText: popup.dateHint
            }
            QQC2.TextField {
                id: startTimeField
                visible: !allDayCheck.checked
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                placeholderText: "HH:MM"
            }
            QQC2.Label {
                visible: !allDayCheck.checked
                text: i18n("for")
            }
            QQC2.SpinBox {
                id: durationSpin
                visible: !allDayCheck.checked
                from: 1
                to: 24
                value: 1
            }
            QQC2.Label {
                visible: !allDayCheck.checked
                text: i18n("h")
            }
        }

        QQC2.TextField {
            id: locationField
            Layout.fillWidth: true
            placeholderText: i18n("Location (optional)")
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            clip: true

            QQC2.TextArea {
                id: descriptionField
                wrapMode: TextEdit.Wrap
                placeholderText: i18n("Description (optional)")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: text !== ""
                color: Kirigami.Theme.negativeTextColor
                text: popup.localError || popup.externalError
            }

            QQC2.Button {
                visible: popup.editMode
                text: popup.confirmingDelete ? i18n("Confirm delete?") : i18n("Delete")
                icon.name: "edit-delete"
                onClicked: {
                    if (popup.confirmingDelete) {
                        confirmTimer.stop();
                        popup.confirmingDelete = false;
                        popup.removeItem(popup.editingItem, popup.isTask);
                    } else {
                        popup.confirmingDelete = true;
                        confirmTimer.restart();
                    }
                }
            }

            QQC2.Button {
                text: popup.editMode ? i18n("Save") : i18n("Add")
                enabled: titleField.text.trim().length > 0 && (popup.editMode || popup.activeCalendars.length > 0)
                onClicked: popup.submit()
            }
        }
    }

    function pad(n) { return (n < 10 ? "0" : "") + n; }

    function formatDateField(d) {
        var dd = pad(d.getDate());
        var mm = pad(d.getMonth() + 1);
        var yyyy = d.getFullYear();
        return popup.dayFirst ? (dd + "-" + mm + "-" + yyyy) : (mm + "-" + dd + "-" + yyyy);
    }

    function formatTimeField(d) {
        return pad(d.getHours()) + ":" + pad(d.getMinutes());
    }

    function parseDateField(text) {
        var m = text.match(/^(\d{1,2})-(\d{1,2})-(\d{4})$/);
        if (!m) return null;
        var a = parseInt(m[1], 10), b = parseInt(m[2], 10), y = parseInt(m[3], 10);
        var day = popup.dayFirst ? a : b;
        var month = popup.dayFirst ? b : a;
        var d = new Date(y, month - 1, day);
        return isNaN(d.getTime()) ? null : d;
    }

    function parseTimeField(text) {
        var m = text.match(/^(\d{1,2}):(\d{2})$/);
        if (!m) return null;
        var h = parseInt(m[1], 10), mnt = parseInt(m[2], 10);
        if (h < 0 || h > 23 || mnt < 0 || mnt > 59) return null;
        return { hours: h, minutes: mnt };
    }

    function submit() {
        localError = "";
        var summary = titleField.text.trim();
        if (summary.length === 0) return;
        var description = descriptionField.text.trim();
        var location = locationField.text.trim();

        var cal = null;
        if (!popup.editMode) {
            cal = popup.activeCalendars[calendarCombo.currentIndex];
            if (!cal) { localError = i18n("Pick a calendar first."); return; }
        }

        if (popup.isTask) {
            var due = null;
            var dueText = dueField.text.trim();
            if (dueText !== "") {
                due = parseDateField(dueText);
                if (!due) { localError = i18n("Due date must be in %1 form.", popup.dateHint); return; }
            }
            if (popup.editMode) popup.saveTask(popup.editingItem, summary, due, description, location);
            else popup.createTask(cal.href, summary, due, description, location);
        } else {
            var startDateText = startDateField.text.trim();
            var startDate = parseDateField(startDateText);
            if (!startDate) { localError = i18n("Start date must be in %1 form.", popup.dateHint); return; }

            var start, end;
            if (allDayCheck.checked) {
                start = startDate;
                end = new Date(startDate);
                end.setDate(end.getDate() + 1);
            } else {
                var timeText = startTimeField.text.trim() || "09:00";
                var time = parseTimeField(timeText);
                if (!time) { localError = i18n("Start time must be in HH:MM form."); return; }
                start = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate(), time.hours, time.minutes);
                end = new Date(start.getTime() + durationSpin.value * 3600000);
            }
            if (popup.editMode) popup.saveEvent(popup.editingItem, summary, start, end, allDayCheck.checked, description, location);
            else popup.createEvent(cal.href, summary, start, end, allDayCheck.checked, description, location);
        }
    }
}
