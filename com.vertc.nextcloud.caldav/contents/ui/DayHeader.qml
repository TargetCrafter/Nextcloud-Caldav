import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/dateutils.js" as DateUtils

RowLayout {
    id: header

    // Either `date` (a day grouping header) or `label`+`count` (a named
    // section like "Overdue" / "No due date") is set, not both.
    property date date
    property string label: ""
    property int count: 0
    // Only "recentlyClosed" sets these - a fold/expand arrow like
    // TaskDelegate's subtask one, for a section whose contents are
    // optional to show at all (unlike "Overdue"/day headers, which are
    // just labels over content that's always there).
    property bool expandable: false
    property bool expanded: true
    // Non-zero only for a task's own nested "Recently closed" mini-section
    // (see main.qml's orderTasksWithHierarchy) - indents it to line up
    // under its parent task, the same depth TaskDelegate itself uses for
    // subtask rows.
    property int depth: 0
    signal toggleRequested()

    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    Layout.bottomMargin: Kirigami.Units.smallSpacing / 2
    Layout.leftMargin: depth * Kirigami.Units.gridUnit
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        visible: header.label === "overdue"
        source: "task-attention"
        color: Kirigami.Theme.negativeTextColor
        Layout.preferredWidth: Kirigami.Units.iconSizes.small
        Layout.preferredHeight: Kirigami.Units.iconSizes.small
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        font.bold: true
        font.pointSize: header.depth > 0 ? Kirigami.Theme.smallFont.pointSize : Kirigami.Theme.defaultFont.pointSize
        color: header.label === "overdue" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        text: header.text()

        MouseArea {
            anchors.fill: parent
            visible: header.expandable
            cursorShape: Qt.PointingHandCursor
            onClicked: header.toggleRequested()
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        opacity: 0.5
    }

    PlasmaComponents3.ToolButton {
        visible: header.expandable
        flat: true
        icon.name: header.expanded ? "arrow-down" : "arrow-right"
        Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
        Layout.preferredHeight: Layout.preferredWidth
        onClicked: header.toggleRequested()
        PlasmaComponents3.ToolTip.text: header.expanded ? i18n("Hide") : i18n("Show")
        PlasmaComponents3.ToolTip.visible: hovered
    }

    function text() {
        if (label === "overdue") return i18np("Overdue (%1)", "Overdue (%1)", count);
        if (label === "dueLater") return i18n("Due later");
        if (label === "noDueDate") return i18n("No due date");
        if (label === "recentlyClosed") return i18np("Recently closed (%1)", "Recently closed (%1)", count);

        var offset = DateUtils.dayOffset(date);
        if (offset === 0) return i18n("Today · %1", Qt.formatDate(date, "d MMMM"));
        if (offset === 1) return i18n("Tomorrow · %1", Qt.formatDate(date, "d MMMM"));
        return Qt.formatDate(date, "dddd · d MMMM");
    }
}
