import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: delegate

    required property var taskData
    signal toggled()
    signal editRequested()

    readonly property bool completed: taskData.status === "COMPLETED"
    readonly property int depth: taskData.depth || 0

    // See EventDelegate.qml for why this must match the row's own margins.
    implicitHeight: row.implicitHeight + Kirigami.Units.mediumSpacing * 2

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        // Matches EventDelegate's card background - the calendar-color
        // accent bar below is what now tells tasks and events apart, the
        // same way it already does between different calendars.
        color: hover.hovered ? Kirigami.Theme.hoverColor : Kirigami.Theme.alternateBackgroundColor
        opacity: hover.hovered ? 1 : 0.35
    }

    // Kept outside the indented RowLayout below and anchored at a fixed
    // position, rather than as the row's first child - a subtask's deeper
    // anchors.leftMargin would otherwise have shifted its own accent bar
    // along with the rest of its content, leaving every task's bar at a
    // different x instead of all lined up in a column.
    Rectangle {
        id: accentBar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Kirigami.Units.mediumSpacing
        anchors.topMargin: Kirigami.Units.mediumSpacing
        anchors.bottomMargin: Kirigami.Units.mediumSpacing
        width: Kirigami.Units.smallSpacing * 0.6
        radius: width / 2
        color: delegate.taskData.calendarColor || Kirigami.Theme.highlightColor
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Kirigami.Units.mediumSpacing
        anchors.leftMargin: Kirigami.Units.mediumSpacing + accentBar.width + Kirigami.Units.smallSpacing +
                             delegate.depth * Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            visible: delegate.depth > 0
            opacity: 0.6
            text: "↳"
        }

        PlasmaComponents3.CheckBox {
            checked: delegate.completed
            onToggled: delegate.toggled()
            Layout.alignment: Qt.AlignTop
        }

        PlasmaComponents3.Label {
            // The calendar-color accent bar above already identifies which
            // calendar this is, the same way it does for events - a
            // separate calendar-name line was redundant.
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.strikeout: delegate.completed
            font.pointSize: delegate.depth > 0 ? Kirigami.Theme.smallFont.pointSize : Kirigami.Theme.defaultFont.pointSize
            opacity: delegate.completed ? 0.6 : 1
            text: delegate.taskData.summary || i18n("(No title)")
        }

        Kirigami.Icon {
            visible: delegate.taskData.priority >= 1 && delegate.taskData.priority <= 4
            source: "task-attention"
            color: Kirigami.Theme.negativeTextColor
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents3.ToolButton {
            visible: hover.hovered
            icon.name: "document-edit"
            onClicked: delegate.editRequested()
            PlasmaComponents3.ToolTip.text: i18n("Edit…")
            PlasmaComponents3.ToolTip.visible: hovered
        }
    }
}
