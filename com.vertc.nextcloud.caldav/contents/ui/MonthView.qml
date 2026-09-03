import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/dateutils.js" as DateUtils

ColumnLayout {
    id: view

    // Event objects (dtstart/dtend/allDay/calendarColor/...) for whichever
    // month is currently shown - independent of the agenda list's own
    // daysAhead window, see main.qml's refreshMonth().
    property var monthEvents: []
    property bool monthLoading: false
    property date monthCursor
    property date selectedDate
    property date currentTime

    signal navigate(int delta)
    signal daySelected(date day)
    signal todayRequested()

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
            text: Qt.formatDate(view.monthCursor, "MMMM yyyy")
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
            model: [i18n("Su"), i18n("Mo"), i18n("Tu"), i18n("We"), i18n("Th"), i18n("Fr"), i18n("Sa")]
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

                    readonly property bool inMonth: cellDate.getMonth() === view.monthCursor.getMonth()
                    readonly property bool isToday: DateUtils.isSameDay(cellDate, view.currentTime)
                    readonly property bool isSelected: DateUtils.isSameDay(cellDate, view.selectedDate)
                    readonly property var dayColors: view.colorsFor(cellDate)

                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.6
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

                        Item {
                            // A plain Item with a hard-fixed height, rather
                            // than relying on the RowLayout below's own
                            // Layout.preferredHeight hint - that was still
                            // letting the row's actual size follow its
                            // content (0 dots vs several), shifting the day
                            // number above it up/down between cells in the
                            // same row. This can't be influenced by the
                            // Repeater's item count at all.
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
    // next-month days.
    function buildWeeks() {
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
