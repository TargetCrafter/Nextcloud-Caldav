import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

import "../code/dateutils.js" as DateUtils

// Small reusable month-grid date picker, opened from ItemFormPopup's date
// fields. Deliberately built the same way MonthView.qml's own week grid is
// (plain Date arithmetic, no extra module) rather than reaching for a
// calendar-picker component from some other Kirigami/QQC2 module, since
// availability of one isn't guaranteed across Plasma versions and this
// widget already has a proven, working pattern for exactly this shape of
// UI.
QQC2.Popup {
    id: picker

    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    width: Kirigami.Units.gridUnit * 16

    // Centered within whatever `parent` the caller assigns (typically the
    // same parent the caller's own enclosing popup centers itself within),
    // rather than trying to precisely anchor under the triggering button -
    // simpler and avoids QML Popup-in-Popup coordinate-mapping pitfalls.
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0

    background: Rectangle {
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Kirigami.Theme.highlightColor
    }

    property date cursor: DateUtils.startOfMonth(new Date())
    signal picked(date day)

    // Opens showing the month containing `initial` (or today, if `initial`
    // is unset/invalid).
    function openFor(initial) {
        cursor = DateUtils.startOfMonth(initial && !isNaN(initial.getTime()) ? initial : new Date());
        picker.open();
    }

    readonly property var weeks: buildWeeks()

    // Same algorithm as MonthView.qml's buildWeeks().
    function buildWeeks() {
        var first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
        var last = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0);
        var start = new Date(first);
        start.setDate(start.getDate() - start.getDay());
        var weeksOut = [];
        var day = new Date(start);
        while (true) {
            var week = [];
            for (var d = 0; d < 7; d++) {
                week.push(new Date(day));
                day.setDate(day.getDate() + 1);
            }
            weeksOut.push(week);
            if (day.getTime() > last.getTime()) break;
        }
        return weeksOut;
    }

    ColumnLayout {
        width: picker.availableWidth
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ToolButton {
                icon.name: "go-previous"
                onClicked: picker.cursor = DateUtils.addMonths(picker.cursor, -1)
            }
            Kirigami.Heading {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                level: 4
                text: Qt.formatDate(picker.cursor, "MMMM yyyy")
            }
            QQC2.ToolButton {
                icon.name: "go-next"
                onClicked: picker.cursor = DateUtils.addMonths(picker.cursor, 1)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: [i18n("Su"), i18n("Mo"), i18n("Tu"), i18n("We"), i18n("Th"), i18n("Fr"), i18n("Sa")]
                delegate: QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: modelData
                }
            }
        }

        Repeater {
            model: picker.weeks

            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: 0

                property var week: modelData

                Repeater {
                    model: parent.week
                    delegate: QQC2.ToolButton {
                        property date cellDate: modelData
                        readonly property bool inMonth: cellDate.getMonth() === picker.cursor.getMonth()
                        readonly property bool isToday: DateUtils.isSameDay(cellDate, new Date())

                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.8
                        flat: !isToday
                        opacity: inMonth ? 1 : 0.35
                        text: cellDate.getDate()
                        onClicked: {
                            picker.picked(cellDate);
                            picker.close();
                        }
                    }
                }
            }
        }

        QQC2.Button {
            Layout.fillWidth: true
            flat: true
            text: i18n("Today")
            onClicked: {
                picker.picked(new Date());
                picker.close();
            }
        }
    }
}
