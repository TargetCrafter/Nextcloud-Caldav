import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: bar

    // [{ href, name, color, kinds }]
    property var calendars: []
    // "task" / "event" / "" - set when the widget is restricted to a single
    // display mode (see main.xml's displayMode), so there's nothing to
    // switch between and the tab row is just noise.
    property string lockedType: ""
    property bool isTask: true
    // Deliberately imperative rather than a binding to lockedType: isTask
    // is also assigned imperatively by the tab row's onCurrentIndexChanged
    // below, and a declarative binding here would get silently clobbered
    // the first time that handler runs (currentIndex reacting to isTask,
    // then writing isTask back, breaking this binding for good).
    onLockedTypeChanged: bar.applyLockedType()
    Component.onCompleted: bar.applyLockedType()
    function applyLockedType() {
        if (lockedType === "task") isTask = true;
        else if (lockedType === "event") isTask = false;
    }
    // Error surfaced from the actual CalDAV write (as opposed to the local
    // field-validation errors below), bound in from outside.
    property string externalError: ""

    signal createTask(string calendarHref, string summary, var due)
    signal createEvent(string calendarHref, string summary, var start, var end, bool allDay)

    readonly property var taskCalendars: calendars.filter(function (c) { return c.kinds.indexOf("VTODO") !== -1; })
    readonly property var eventCalendars: calendars.filter(function (c) { return c.kinds.indexOf("VEVENT") !== -1; })
    readonly property var activeCalendars: isTask ? taskCalendars : eventCalendars

    Layout.fillWidth: true
    Layout.margins: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    property string localError: ""

    PlasmaComponents3.TabBar {
        id: typeBar
        visible: bar.lockedType === ""
        // TabBar splits its own width evenly between tabs; left to its
        // implicit width it ends up too narrow for "Event", wrapping the
        // text mid-word. A fixed, generous preferred width avoids that
        // without stretching across the whole bar.
        Layout.fillWidth: false
        Layout.preferredWidth: Kirigami.Units.gridUnit * 9
        currentIndex: bar.isTask ? 0 : 1
        onCurrentIndexChanged: {
            bar.isTask = currentIndex === 0;
            bar.localError = "";
        }

        PlasmaComponents3.TabButton { text: i18n("Task") }
        PlasmaComponents3.TabButton { text: i18n("Event") }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: titleField
            Layout.fillWidth: true
            placeholderText: bar.isTask ? i18n("New task…") : i18n("New event…")
            onAccepted: bar.submit()
        }

        QQC2.ComboBox {
            id: calendarCombo
            Layout.preferredWidth: Kirigami.Units.gridUnit * 9
            model: bar.activeCalendars.map(function (c) { return c.name; })
            enabled: bar.activeCalendars.length > 0
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: bar.isTask
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: i18n("Due:") }
        QQC2.TextField {
            id: dueField
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            placeholderText: i18n("YYYY-MM-DD (optional)")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !bar.isTask
        spacing: Kirigami.Units.smallSpacing

        QQC2.CheckBox {
            id: allDayCheck
            text: i18n("All day")
        }
        QQC2.TextField {
            id: startDateField
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            placeholderText: "YYYY-MM-DD"
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

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: text !== ""
            color: Kirigami.Theme.negativeTextColor
            text: bar.localError || bar.externalError
        }

        QQC2.Button {
            text: i18n("Add")
            enabled: titleField.text.trim().length > 0 && bar.activeCalendars.length > 0
            onClicked: bar.submit()
        }
    }

    function pad(n) { return (n < 10 ? "0" : "") + n; }

    function todayText() {
        var d = new Date();
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    }

    function parseDateField(text) {
        var m = text.match(/^(\d{4})-(\d{2})-(\d{2})$/);
        if (!m) return null;
        var d = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
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
        var cal = activeCalendars[calendarCombo.currentIndex];
        if (!cal) {
            localError = i18n("Pick a calendar first.");
            return;
        }
        var summary = titleField.text.trim();
        if (summary.length === 0) return;

        if (isTask) {
            var due = null;
            var dueText = dueField.text.trim();
            if (dueText !== "") {
                due = parseDateField(dueText);
                if (!due) { localError = i18n("Due date must be in YYYY-MM-DD form."); return; }
            }
            createTask(cal.href, summary, due);
            dueField.text = "";
        } else {
            var startDateText = startDateField.text.trim() || todayText();
            var startDate = parseDateField(startDateText);
            if (!startDate) { localError = i18n("Start date must be in YYYY-MM-DD form."); return; }

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
            createEvent(cal.href, summary, start, end, allDayCheck.checked);
            startDateField.text = "";
            startTimeField.text = "";
        }
        titleField.text = "";
    }
}
