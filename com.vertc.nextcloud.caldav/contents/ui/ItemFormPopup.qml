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
    // Capped the same way as width - on a short screen/panel the form's
    // natural content height (more rows now than when this was first
    // written, e.g. the split event date/time rows) can exceed available
    // vertical space, clipping the bottom of the popup instead of
    // shrinking or scrolling it. Sized off mainColumn's own implicitHeight
    // rather than popup's own implicitHeight/contentHeight - which would
    // be circular once that content sits inside a height-constrained
    // ScrollView below - so the popup keeps its natural compact size when
    // there's room, and caps itself (scrolling the rest) when there isn't.
    height: parent ? Math.min(mainColumn.implicitHeight + topPadding + bottomPadding, parent.height - Kirigami.Units.gridUnit * 2)
                   : mainColumn.implicitHeight + topPadding + bottomPadding

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
    // Set (create mode only) when this popup was opened via a task's "+"
    // subtask button - forces task type, skips the calendar picker (a
    // subtask always goes in its parent's own calendar/task list), and
    // gets tagged with RELATED-TO on save.
    property var parentTask: null

    // [{ href, name, color, kinds }]
    property var calendars: []
    property string externalError: ""
    // Prefilled start/due date for a new item: the day selected in the
    // month-calendar view, or today otherwise.
    property date defaultDate: new Date()
    // Which text field the shared date-picker/time-picker popup should
    // write its result into (dueField/startDateField, dueTimeField/
    // startTimeField) - set right before opening the relevant picker.
    property var activeDateField: null
    property var activeTimeField: null

    signal createTask(string calendarHref, string summary, var due, bool dueHasTime, string description, string location, string parentUid, int priority)
    signal createEvent(string calendarHref, string summary, var start, var end, bool allDay, string description, string location)
    signal saveTask(var task, string summary, var due, bool dueHasTime, string description, string location, int priority, string status, int percentComplete)
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

    function openForCreate(parentTask) {
        popup.editMode = false;
        popup.editingItem = null;
        popup.parentTask = parentTask || null;
        localError = "";
        confirmingDelete = false;
        confirmTimer.stop();
        if (popup.parentTask) popup.isTask = true;
        else if (popup.lockedType === "task") popup.isTask = true;
        else if (popup.lockedType === "event") popup.isTask = false;
        titleField.text = "";
        var text = popup.formatDateField(popup.defaultDate);
        dueField.text = "";
        dueTimeField.text = "";
        startDateField.text = text;
        startTimeField.text = "";
        allDayCheck.checked = false;
        durationSpin.value = 1;
        descriptionField.text = "";
        locationField.text = "";
        priorityCombo.currentIndex = 0;
        popup.open();
    }

    function openForEdit(item, taskFlag) {
        popup.editMode = true;
        popup.editingItem = item;
        popup.parentTask = null;
        popup.isTask = taskFlag;
        localError = "";
        confirmingDelete = false;
        confirmTimer.stop();
        titleField.text = item.summary || "";
        descriptionField.text = item.description || "";
        locationField.text = item.location || "";
        if (taskFlag) {
            dueField.text = item.due ? popup.formatDateField(item.due) : "";
            dueTimeField.text = (item.due && !item.dueAllDay) ? popup.formatTimeField(item.due) : "";
            priorityCombo.currentIndex = popup.priorityToIndex(item.priority || 0);
            statusCombo.currentIndex = popup.statusToIndex(item.status || "NEEDS-ACTION");
            percentSpin.value = item.percentComplete || 0;
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

    // Scrolls the whole form when its capped height (see above) is
    // shorter than the content actually needs, instead of just cutting it
    // off at the popup's own bottom edge.
    QQC2.ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

    ColumnLayout {
        id: mainColumn
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
                    if (popup.parentTask) return i18n("New subtask");
                    return popup.isTask ? i18n("New task") : i18n("New event");
                }
            }

            PlasmaComponents3.ToolButton {
                icon.name: "window-close"
                onClicked: popup.close()
                PlasmaComponents3.ToolTip.text: i18n("Close")
                PlasmaComponents3.ToolTip.visible: hovered
            }
        }

        PlasmaComponents3.TabBar {
            id: typeBar
            visible: !popup.editMode && popup.lockedType === "" && !popup.parentTask
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
            visible: !popup.editMode && !popup.parentTask
            model: popup.activeCalendars.map(function (c) { return c.name; })
            enabled: popup.activeCalendars.length > 0
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: !popup.editMode && !!popup.parentTask
            elide: Text.ElideRight
            opacity: 0.7
            // Renders another task's server-supplied summary - see
            // EventDelegate.qml's summary Label for why this must stay
            // plain text.
            textFormat: Text.PlainText
            text: i18n("Subtask of: %1", popup.parentTask ? (popup.parentTask.summary || i18n("(No title)")) : "")
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
            QQC2.ToolButton {
                icon.name: "x-office-calendar"
                onClicked: {
                    popup.activeDateField = dueField;
                    datePicker.openFor(popup.parseDateField(dueField.text.trim()) || popup.defaultDate);
                }
                QQC2.ToolTip.text: i18n("Pick a date")
                QQC2.ToolTip.visible: hovered
            }
            QQC2.TextField {
                id: dueTimeField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                placeholderText: "HH:MM"
            }
            QQC2.ToolButton {
                icon.name: "clock"
                onClicked: {
                    popup.activeTimeField = dueTimeField;
                    var t = popup.parseTimeField(dueTimeField.text.trim());
                    timePicker.openFor(t ? t.hours : undefined, t ? t.minutes : undefined);
                }
                QQC2.ToolTip.text: i18n("Pick a time")
                QQC2.ToolTip.visible: hovered
            }
        }

        // Priority and Status are split into their own rows, rather than
        // sharing one - this popup's fixed width has overflowed before
        // (see the event date/time rows' own history) when a row's
        // controls plus their labels didn't fit, and Status's own item
        // text ("Needs action", "In progress", ...) run long enough,
        // especially translated, to risk exactly that here too.
        RowLayout {
            Layout.fillWidth: true
            visible: popup.isTask
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("Priority:") }
            QQC2.ComboBox {
                id: priorityCombo
                Layout.fillWidth: true
                model: [i18n("None"), i18n("Low"), i18n("Medium"), i18n("High")]
            }
        }

        // Status is only offered once a task actually exists - a new task
        // is always created NEEDS-ACTION (creating one that's already
        // done/cancelled isn't a normal case worth a control for),
        // matching how the completed-toggle checkbox has always worked.
        RowLayout {
            Layout.fillWidth: true
            visible: popup.isTask && popup.editMode
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("Status:") }
            QQC2.ComboBox {
                id: statusCombo
                Layout.fillWidth: true
                model: [i18n("Needs action"), i18n("In progress"), i18n("Completed"), i18n("Cancelled")]
            }
        }

        // Only meaningful (and only offered) while "In progress" is
        // selected above - Needs action/Cancelled are always 0% and
        // Completed is always 100%, same as before this field existed at
        // all (see submit()'s own status->percent mapping).
        RowLayout {
            Layout.fillWidth: true
            visible: popup.isTask && popup.editMode && statusCombo.currentIndex === 1
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("% complete:") }
            QQC2.SpinBox {
                id: percentSpin
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 5
                textFromValue: (value) => i18n("%1%", value)
                valueFromText: (text) => parseInt(text, 10) || 0
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
            QQC2.ToolButton {
                icon.name: "x-office-calendar"
                onClicked: {
                    popup.activeDateField = startDateField;
                    datePicker.openFor(popup.parseDateField(startDateField.text.trim()) || popup.defaultDate);
                }
                QQC2.ToolTip.text: i18n("Pick a date")
                QQC2.ToolTip.visible: hovered
            }
        }

        // Split into its own row (rather than tacked onto the date row
        // above) since with the date/time picker buttons added, the two
        // rows' combined content no longer fits the popup's fixed width -
        // it was overflowing past the popup's own edge instead of wrapping.
        RowLayout {
            Layout.fillWidth: true
            visible: !popup.isTask && !allDayCheck.checked
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: startTimeField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                placeholderText: "HH:MM"
            }
            QQC2.ToolButton {
                icon.name: "clock"
                onClicked: {
                    popup.activeTimeField = startTimeField;
                    var t = popup.parseTimeField(startTimeField.text.trim());
                    timePicker.openFor(t ? t.hours : undefined, t ? t.minutes : undefined);
                }
                QQC2.ToolTip.text: i18n("Pick a time")
                QQC2.ToolTip.visible: hovered
            }
            QQC2.Label {
                text: i18n("for")
            }
            QQC2.SpinBox {
                id: durationSpin
                from: 1
                to: 24
                value: 1
            }
            QQC2.Label {
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
                // Sonnet spellcheck flags any word outside the active
                // dictionary (e.g. non-English text) in red with an
                // underline, which reads as a rendering bug in a field
                // that's just free-form notes - disable it here.
                Kirigami.SpellCheck.enabled: false
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
                enabled: titleField.text.trim().length > 0 && (popup.editMode || popup.parentTask || popup.activeCalendars.length > 0)
                onClicked: popup.submit()
            }
        }
    }
    }

    DatePickerPopup {
        id: datePicker
        parent: popup.parent
        onPicked: (day) => {
            if (popup.activeDateField) popup.activeDateField.text = popup.formatDateField(day);
        }
    }

    TimePickerPopup {
        id: timePicker
        parent: popup.parent
        onPicked: (hours, minutes) => {
            if (popup.activeTimeField) popup.activeTimeField.text = popup.pad(hours) + ":" + popup.pad(minutes);
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

    // RFC 5545 priority is 1 (highest) to 9 (lowest), 0 = undefined - the
    // same High(1-4)/Medium(5)/Low(6-9)/None(0) bucketing most calendar
    // apps (Thunderbird, Outlook, Nextcloud's own web UI) show instead of
    // the raw 9-level scale, and the same boundaries TaskRow.qml's own
    // priority icon already uses (1-4). Saving always writes each
    // bucket's own canonical value (9/5/1), even when the task's actual
    // priority was some other value in that bucket (e.g. 3) - expected,
    // matching how those other apps' equally-simple pickers behave too.
    function priorityToIndex(p) {
        if (p >= 1 && p <= 4) return 3; // High
        if (p === 5) return 2; // Medium
        if (p >= 6 && p <= 9) return 1; // Low
        return 0; // None
    }

    function indexToPriority(idx) {
        return [0, 9, 5, 1][idx] || 0;
    }

    function statusToIndex(status) {
        switch (status) {
        case "IN-PROCESS": return 1;
        case "COMPLETED": return 2;
        case "CANCELLED": return 3;
        default: return 0; // NEEDS-ACTION
        }
    }

    function indexToStatus(idx) {
        return ["NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"][idx] || "NEEDS-ACTION";
    }

    function submit() {
        localError = "";
        var summary = titleField.text.trim();
        if (summary.length === 0) return;
        var description = descriptionField.text.trim();
        var location = locationField.text.trim();

        var cal = null;
        if (!popup.editMode && !popup.parentTask) {
            cal = popup.activeCalendars[calendarCombo.currentIndex];
            if (!cal) { localError = i18n("Pick a calendar first."); return; }
        }

        if (popup.isTask) {
            var due = null;
            var dueHasTime = false;
            var dueText = dueField.text.trim();
            if (dueText !== "") {
                due = parseDateField(dueText);
                if (!due) { localError = i18n("Due date must be in %1 form.", popup.dateHint); return; }
                var dueTimeText = dueTimeField.text.trim();
                if (dueTimeText !== "") {
                    var dueTime = parseTimeField(dueTimeText);
                    if (!dueTime) { localError = i18n("Due time must be in HH:MM form."); return; }
                    due = new Date(due.getFullYear(), due.getMonth(), due.getDate(), dueTime.hours, dueTime.minutes);
                    dueHasTime = true;
                }
            }
            var priority = popup.indexToPriority(priorityCombo.currentIndex);
            if (popup.editMode) {
                var status = popup.indexToStatus(statusCombo.currentIndex);
                // Needs action/Cancelled are always 0%, Completed always
                // 100% - only In progress has a percentage actually worth
                // asking about (see percentSpin's own visibility above).
                var percentComplete = status === "COMPLETED" ? 100 : (status === "IN-PROCESS" ? percentSpin.value : 0);
                popup.saveTask(popup.editingItem, summary, due, dueHasTime, description, location, priority, status, percentComplete);
            } else {
                var calendarHref = popup.parentTask ? popup.parentTask.calendarHref : cal.href;
                popup.createTask(calendarHref, summary, due, dueHasTime, description, location, popup.parentTask ? popup.parentTask.uid : "", priority);
            }
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
