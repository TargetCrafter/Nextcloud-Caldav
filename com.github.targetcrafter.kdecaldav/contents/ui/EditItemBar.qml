import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Edit/delete panel for a single existing event or task. Deliberately a
// separate component from AddItemBar rather than a shared one with a mode
// flag: the two have different field sets (no calendar picker or type tabs
// here - both are fixed for an existing item) and different submit
// semantics (PUT-with-etag/DELETE vs. POST-style creation), and keeping
// them apart avoids entangling AddItemBar's already-nontrivial
// lockedType/isTask handling with a second mode.
ColumnLayout {
    id: bar

    property bool isTask: true
    property var item: null

    // Error surfaced from the actual CalDAV write, bound in from outside.
    property string externalError: ""

    signal saveTask(string summary, var due)
    signal saveEvent(string summary, var start, var end, bool allDay)
    signal remove()
    signal cancelled()

    // Same locale-based day/month order detection as AddItemBar - see its
    // comment for why a hand-rolled numeric mask is used instead of the
    // locale's own (possibly 2-digit-year, differently-separated) pattern.
    readonly property bool dayFirst: bar.detectDayFirst()
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

    Layout.fillWidth: true
    Layout.margins: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    property string localError: ""
    property bool confirmingDelete: false

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: bar.confirmingDelete = false
    }

    // (Re)loads the fields from `item` whenever a new one is opened for
    // editing - item is only ever swapped while this bar is hidden/shown
    // fresh (see FullRepresentation's openEdit*), never mutated in place.
    onItemChanged: bar.loadFromItem()
    Component.onCompleted: bar.loadFromItem()

    function loadFromItem() {
        confirmingDelete = false;
        confirmTimer.stop();
        localError = "";
        if (!item) return;
        titleField.text = item.summary || "";
        if (isTask) {
            dueField.text = item.due ? bar.formatDateField(item.due) : "";
        } else {
            allDayCheck.checked = !!item.allDay;
            startDateField.text = item.dtstart ? bar.formatDateField(item.dtstart) : "";
            startTimeField.text = (item.dtstart && !item.allDay) ? bar.formatTimeField(item.dtstart) : "";
            var durationHours = (item.dtstart && item.dtend) ? Math.max(1, Math.round((item.dtend.getTime() - item.dtstart.getTime()) / 3600000)) : 1;
            durationSpin.value = durationHours;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            text: bar.isTask ? i18n("Edit task") : i18n("Edit event")
            font.bold: true
        }

        QQC2.Button {
            text: i18n("Cancel")
            flat: true
            onClicked: bar.cancelled()
        }
    }

    QQC2.TextField {
        id: titleField
        Layout.fillWidth: true
        placeholderText: bar.isTask ? i18n("Task title") : i18n("Event title")
        onAccepted: bar.submit()
    }

    RowLayout {
        Layout.fillWidth: true
        visible: bar.isTask
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: i18n("Due:") }
        QQC2.TextField {
            id: dueField
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            placeholderText: bar.dateHint + i18n(" (optional)")
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
            placeholderText: bar.dateHint
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
            text: bar.confirmingDelete ? i18n("Confirm delete?") : i18n("Delete")
            icon.name: "edit-delete"
            onClicked: {
                if (bar.confirmingDelete) {
                    confirmTimer.stop();
                    bar.confirmingDelete = false;
                    bar.remove();
                } else {
                    bar.confirmingDelete = true;
                    confirmTimer.restart();
                }
            }
        }

        QQC2.Button {
            text: i18n("Save")
            enabled: titleField.text.trim().length > 0
            onClicked: bar.submit()
        }
    }

    function pad(n) { return (n < 10 ? "0" : "") + n; }

    function formatDateField(d) {
        var dd = pad(d.getDate());
        var mm = pad(d.getMonth() + 1);
        var yyyy = d.getFullYear();
        return bar.dayFirst ? (dd + "-" + mm + "-" + yyyy) : (mm + "-" + dd + "-" + yyyy);
    }

    function formatTimeField(d) {
        return pad(d.getHours()) + ":" + pad(d.getMinutes());
    }

    function parseDateField(text) {
        var m = text.match(/^(\d{1,2})-(\d{1,2})-(\d{4})$/);
        if (!m) return null;
        var a = parseInt(m[1], 10), b = parseInt(m[2], 10), y = parseInt(m[3], 10);
        var day = bar.dayFirst ? a : b;
        var month = bar.dayFirst ? b : a;
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

        if (isTask) {
            var due = null;
            var dueText = dueField.text.trim();
            if (dueText !== "") {
                due = parseDateField(dueText);
                if (!due) { localError = i18n("Due date must be in %1 form.", bar.dateHint); return; }
            }
            bar.saveTask(summary, due);
        } else {
            var startDateText = startDateField.text.trim();
            var startDate = parseDateField(startDateText);
            if (!startDate) { localError = i18n("Start date must be in %1 form.", bar.dateHint); return; }

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
            bar.saveEvent(summary, start, end, allDayCheck.checked);
        }
    }
}
