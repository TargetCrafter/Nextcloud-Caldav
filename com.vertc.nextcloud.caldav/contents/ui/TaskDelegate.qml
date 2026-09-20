import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: delegate

    required property var taskData
    signal toggled()
    signal editRequested()
    signal addSubtaskRequested()
    signal toggleCollapseRequested()

    readonly property bool completed: taskData.status === "COMPLETED"
    readonly property int depth: taskData.depth || 0
    // Stamped by main.qml's orderTasksWithHierarchy: childCount counts
    // every descendant (not just direct subtasks) a collapsed task hides;
    // collapsed reflects the persisted per-task fold state. Both are only
    // meaningful (childCount > 0) on a task that actually has subtasks.
    readonly property int childCount: taskData.childCount || 0
    readonly property bool collapsed: !!taskData.collapsed

    // Zero for a subtask (or a "Recently closed" subtask row) - it's a
    // continuation of its parent's family, and agendaList's own spacing is
    // 0 (see FullRepresentation.qml), so it sits flush against the row
    // above with no inter-item gap to bridge. Non-zero only for a row that
    // starts a new family (a top-level task), so there's still visible
    // breathing room before it. This replaces the old approach of each row
    // drawing its accent bar past its own edges into the ListView's
    // between-item spacing - which left a visible seam depending on paint
    // order - with a gap that's just ordinary content height, built into
    // this row's own implicitHeight, so a continuing row's bar can start
    // exactly where the previous row's bar ended.
    readonly property real topGap: delegate.depth > 0 ? 0 : Kirigami.Units.smallSpacing

    // See EventDelegate.qml for why this must match the row's own margins.
    implicitHeight: topGap + row.implicitHeight + Kirigami.Units.mediumSpacing * 2

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: delegate.topGap
        anchors.bottom: parent.bottom
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
    //
    // A subtask row (depth > 0) reaches its own top edge exactly (no
    // topGap, see above), and a task with subtasks shown below it
    // (childCount > 0 && !collapsed) reaches its own bottom edge exactly -
    // and since the next row in either case sits flush against this one
    // (agendaList.spacing is 0, and a continuing row's own topGap is 0),
    // the two bars' edges land on the exact same y with nothing to bridge,
    // so they read as one continuous line. DayHeader.qml's own accentBar
    // (for a task's "Recently closed" subtask heading) works the same way.
    Rectangle {
        id: accentBar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Kirigami.Units.mediumSpacing
        anchors.topMargin: delegate.depth > 0 ? 0 : delegate.topGap + Kirigami.Units.mediumSpacing
        anchors.bottomMargin: (delegate.childCount > 0 && !delegate.collapsed) ? 0 : Kirigami.Units.mediumSpacing
        width: Kirigami.Units.smallSpacing * 0.6
        radius: width / 2
        color: delegate.taskData.calendarColor || Kirigami.Theme.highlightColor
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: delegate.topGap + Kirigami.Units.mediumSpacing
        anchors.bottomMargin: Kirigami.Units.mediumSpacing
        anchors.rightMargin: Kirigami.Units.mediumSpacing
        anchors.leftMargin: Kirigami.Units.mediumSpacing + accentBar.width + Kirigami.Units.smallSpacing +
                             delegate.depth * Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.CheckBox {
            checked: delegate.completed
            onToggled: delegate.toggled()
            Layout.alignment: Qt.AlignVCenter
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
            // See EventDelegate.qml's summary Label for why this must be
            // plain text: this renders a server-supplied task summary.
            textFormat: Text.PlainText
            text: delegate.taskData.summary || i18n("(No title)")
        }

        // Positioned right after the (fillWidth) summary Label and before
        // every other fixed-width item in this row on purpose: these
        // buttons only appearing on hover shrink the summary Label by
        // exactly their own width when they do, which leaves everything
        // after them - the subtask badge/arrow, the priority icon - at the
        // same on-screen position either way. Putting them anywhere past
        // those would instead have made *them* jump left/right every time
        // the row was hovered.
        //
        // Only offered on a top-level task (depth 0), not on a subtask
        // itself - this app's hierarchy is intentionally one level deep,
        // matching how orderTasksWithHierarchy/groupRootOf already treat it.
        PlasmaComponents3.ToolButton {
            visible: hover.hovered && delegate.depth === 0
            icon.name: "list-add"
            onClicked: delegate.addSubtaskRequested()
            PlasmaComponents3.ToolTip.text: i18n("Add subtask…")
            PlasmaComponents3.ToolTip.visible: hovered
        }

        PlasmaComponents3.ToolButton {
            visible: hover.hovered
            icon.name: "document-edit"
            onClicked: delegate.editRequested()
            PlasmaComponents3.ToolTip.text: i18n("Edit…")
            PlasmaComponents3.ToolTip.visible: hovered
        }

        PlasmaComponents3.Label {
            // Subtask count, folded task's own row only - see childCount's
            // declaration above. StyledText (unlike the summary/location
            // Labels' locked-down PlainText) is safe here since the only
            // content is our own integer count, never server-supplied text.
            visible: delegate.childCount > 0
            opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            textFormat: Text.StyledText
            text: "<sup>" + delegate.childCount + "</sup>"
        }

        PlasmaComponents3.ToolButton {
            visible: delegate.childCount > 0
            flat: true
            icon.name: delegate.collapsed ? "arrow-right" : "arrow-down"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
            Layout.preferredHeight: Layout.preferredWidth
            onClicked: delegate.toggleCollapseRequested()
            PlasmaComponents3.ToolTip.text: delegate.collapsed ? i18n("Show subtasks") : i18n("Hide subtasks")
            PlasmaComponents3.ToolTip.visible: hovered
        }

        Kirigami.Icon {
            visible: delegate.taskData.priority >= 1 && delegate.taskData.priority <= 4
            source: "task-attention"
            color: Kirigami.Theme.negativeTextColor
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
    }
}
