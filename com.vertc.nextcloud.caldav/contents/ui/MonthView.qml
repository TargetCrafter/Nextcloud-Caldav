import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/dateutils.js" as DateUtils

ColumnLayout {
    id: view

    // Event objects (dtstart/dtend/allDay/calendarColor/...) for whichever
    // period is currently shown - independent of the agenda list's own
    // daysAhead window, see main.qml's refreshMonth().
    property var monthEvents: []
    property bool monthLoading: false
    property date monthCursor
    property date selectedDate: new Date()
    property date currentTime
    // Mirrors plasmoid.configuration.viewMode directly: 1 = Month (a full
    // month grid), 2 = Week (one Sunday-Saturday row), 3 = WorkWeek (one
    // Monday-Friday row). List (0) never instantiates this component.
    property int viewMode: 1

    signal navigate(int delta)
    signal daySelected(date day)
    signal todayRequested()

    readonly property bool weekMode: viewMode === 2 || viewMode === 3
    readonly property var weeks: buildWeeks()

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.ToolButton {
            icon.name: "go-previous"
            onClicked: view.navigate(-1)
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            level: 3
            text: view.weekMode ? view.weekRangeLabel() : Qt.formatDate(view.monthCursor, "MMMM yyyy")
        }

        PlasmaComponents3.BusyIndicator {
            running: view.monthLoading
            visible: running
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
        }

        PlasmaComponents3.ToolButton {
            text: i18n("Today")
            onClicked: view.todayRequested()
        }

        PlasmaComponents3.ToolButton {
            icon.name: "go-next"
            onClicked: view.navigate(1)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
            // WorkWeek drops the weekend columns entirely, not just dims
            // them - there's no cell for Saturday/Sunday to line the
            // header up with otherwise.
            model: view.viewMode === 3 /* WorkWeek */
                   ? [i18n("Mo"), i18n("Tu"), i18n("We"), i18n("Th"), i18n("Fr")]
                   : [i18n("Su"), i18n("Mo"), i18n("Tu"), i18n("We"), i18n("Th"), i18n("Fr"), i18n("Sa")]
            delegate: PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: modelData
            }
        }
    }

    Repeater {
        model: view.weeks

        delegate: RowLayout {
            Layout.fillWidth: true
            spacing: 0

            property var week: modelData

            Repeater {
                model: parent.week

                delegate: Rectangle {
                    id: cell

                    // Mirrors the itemData: modelData pattern used elsewhere
                    // in this codebase (e.g. FullRepresentation.qml's
                    // delegate Loader) rather than a "required property"
                    // redeclaration of modelData.
                    property date cellDate: modelData

                    // Week/WorkWeek mode has no "other month" days to dim -
                    // every visible cell belongs to the one week shown.
                    readonly property bool inMonth: view.weekMode || cellDate.getMonth() === view.monthCursor.getMonth()
                    readonly property bool isToday: DateUtils.isSameDay(cellDate, view.currentTime)
                    readonly property bool isSelected: DateUtils.isSameDay(cellDate, view.selectedDate)
                    readonly property var dayColors: view.colorsFor(cellDate)
                    // Only computed in Week/WorkWeek mode - Month's cells
                    // are too narrow for event titles and stay dot-only.
                    readonly property var dayEvents: view.weekMode ? view.eventsFor(cellDate) : []

                    Layout.fillWidth: true
                    // A single week row can afford to be much taller than
                    // one of up to six month rows, and Week/WorkWeek's own
                    // per-cell event titles (below) need the room.
                    Layout.preferredHeight: view.weekMode ? Kirigami.Units.gridUnit * 7 : Kirigami.Units.gridUnit * 2.6
                    radius: Kirigami.Units.cornerRadius
                    // Selected = filled, today = outlined - independent of
                    // each other, so a selected today gets both at once
                    // rather than one replacing the other.
                    color: isSelected ? Kirigami.Theme.highlightColor : "transparent"
                    border.width: isToday ? 2 : 0
                    border.color: Kirigami.Theme.highlightColor

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing / 2
                        spacing: 2

                        PlasmaComponents3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            opacity: cell.inMonth ? 1 : 0.35
                            font.bold: cell.isToday
                            color: cell.isSelected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                            text: cell.cellDate.getDate()
                        }

                        // Month mode: a small dot per distinct calendar
                        // color that day.
                        Item {
                            // A plain Item with a hard-fixed height, rather
                            // than relying on the RowLayout below's own
                            // Layout.preferredHeight hint - that was still
                            // letting the row's actual size follow its
                            // content (0 dots vs several), shifting the day
                            // number above it up/down between cells in the
                            // same row. This can't be influenced by the
                            // Repeater's item count at all.
                            visible: !view.weekMode
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: dotsRow.implicitWidth
                            Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.6

                            RowLayout {
                                id: dotsRow
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing / 2

                                Repeater {
                                    model: cell.dayColors
                                    delegate: Rectangle {
                                        width: Kirigami.Units.smallSpacing * 1.6
                                        height: width
                                        radius: width / 2
                                        color: modelData
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.35)
                                    }
                                }
                            }
                        }

                        // Week/WorkWeek mode: a single row's cells are tall
                        // enough to name a few of the day's events
                        // directly, not just show a colored dot per
                        // calendar - click the day for the full list
                        // (below, in the day-detail panel) if there's more.
                        ColumnLayout {
                            visible: view.weekMode
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 1

                            Repeater {
                                model: cell.dayEvents.slice(0, 3)
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    Rectangle {
                                        Layout.preferredWidth: Kirigami.Units.smallSpacing
                                        Layout.preferredHeight: width
                                        radius: width / 2
                                        color: modelData.calendarColor || Kirigami.Theme.highlightColor
                                    }

                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        color: cell.isSelected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                        // Renders a server-supplied event
                                        // summary - see EventDelegate.qml's
                                        // own summary Label for why this
                                        // must stay plain text.
                                        textFormat: Text.PlainText
                                        text: modelData.summary || i18n("(No title)")
                                    }
                                }
                            }

                            PlasmaComponents3.Label {
                                visible: cell.dayEvents.length > 3
                                Layout.fillWidth: true
                                opacity: 0.7
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: cell.isSelected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                text: i18n("+%1 more", cell.dayEvents.length - 3)
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: view.daySelected(cell.cellDate)
                    }
                }
            }
        }
    }

    // Rows only as far as the month's last day needs, rather than always
    // padding out to a fixed 6 - most months only need 5 (some still need
    // 6, when the month both starts late in its first week and runs a full
    // 31/30 days), but none should get a trailing row made up entirely of
    // next-month days. Week/WorkWeek mode is always exactly one row, built
    // from whichever Sunday-Saturday week monthCursor falls in.
    function buildWeeks() {
        if (view.weekMode) {
            var wstart = new Date(view.monthCursor);
            wstart.setDate(wstart.getDate() - wstart.getDay());
            var wdays = [];
            for (var wd = 0; wd < 7; wd++) { wdays.push(new Date(wstart)); wstart.setDate(wstart.getDate() + 1); }
            return [view.viewMode === 3 /* WorkWeek */ ? wdays.slice(1, 6) : wdays];
        }

        var first = new Date(monthCursor.getFullYear(), monthCursor.getMonth(), 1);
        var last = new Date(monthCursor.getFullYear(), monthCursor.getMonth() + 1, 0);
        var start = new Date(first);
        start.setDate(start.getDate() - start.getDay());
        var weeks = [];
        var day = new Date(start);
        while (true) {
            var week = [];
            for (var d = 0; d < 7; d++) {
                week.push(new Date(day));
                day.setDate(day.getDate() + 1);
            }
            weeks.push(week);
            if (day.getTime() > last.getTime()) break;
        }
        return weeks;
    }

    // "15 – 21 Sep 2026" for the Sunday-Saturday week containing
    // monthCursor, shortening to just a day number on the start side when
    // start/end share a month and year - WorkWeek mode still labels the
    // full Sunday-Saturday week, even though only Monday-Friday are shown,
    // so the heading doesn't silently disagree with what "this week"
    // means elsewhere in the widget (e.g. the agenda list's own day
    // headers, which also use a Sunday-Saturday week).
    function weekRangeLabel() {
        var start = new Date(view.monthCursor);
        start.setDate(start.getDate() - start.getDay());
        var end = new Date(start);
        end.setDate(end.getDate() + 6);
        var startText = (start.getMonth() === end.getMonth() && start.getFullYear() === end.getFullYear())
                         ? Qt.formatDate(start, "d")
                         : Qt.formatDate(start, "d MMM");
        return startText + " – " + Qt.formatDate(end, "d MMM yyyy");
    }

    // Up to a handful of a day's events, all-day first then by start time -
    // same ordering FullRepresentation's own day-detail panel uses.
    // Week/WorkWeek mode only (see the per-cell event-preview list above).
    function eventsFor(date) {
        var list = view.monthEvents.filter(function (e) {
            return e.dtstart && DateUtils.isSameDay(e.dtstart, date);
        });
        list.sort(function (a, b) {
            if (a.allDay !== b.allDay) return a.allDay ? -1 : 1;
            return a.dtstart.getTime() - b.dtstart.getTime();
        });
        return list;
    }

    // Up to 4 distinct calendar colors for events on this day.
    function colorsFor(date) {
        var seen = {};
        var colors = [];
        view.monthEvents.forEach(function (e) {
            if (!e.dtstart || !DateUtils.isSameDay(e.dtstart, date)) return;
            var c = e.calendarColor || Kirigami.Theme.highlightColor;
            if (seen[c]) return;
            seen[c] = true;
            colors.push(c);
        });
        return colors.slice(0, 4);
    }
}
