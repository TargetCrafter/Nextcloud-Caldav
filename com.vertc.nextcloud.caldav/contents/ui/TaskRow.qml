import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// A single task or subtask line inside a TaskFamilyCard (see
// TaskFamilyCard.qml) - just the checkbox/title/buttons row, indented by
// its own depth. Deliberately has no accent bar and no background of its
// own: the card around it draws one shared bar and one shared background
// for the whole family (a task plus its subtasks and its own "Recently
// closed" subtask rows), so they read as one card instead of independent
// rows that have to line up pixel-perfect with their neighbors to look
// continuous - which repeatedly failed to look right in practice.
Item {
    id: delegate

    required property var taskData
    signal toggled()
    signal editRequested()
    signal addSubtaskRequested()
    signal toggleCollapseRequested()

    readonly property bool completed: taskData.status === "COMPLETED"
    readonly property bool cancelled: taskData.status === "CANCELLED"
    readonly property bool inProgress: taskData.status === "IN-PROCESS"
    // Defaults to taskData's own stamped depth (see main.qml's
    // orderTasksWithHierarchy), but can be overridden explicitly instead -
    // see TaskFamilyCard.qml's "Recently completed" row wiring, which
    // passes it straight from the row's own wrapper rather than relying
    // on taskData.depth - a task object that's also being rendered
    // elsewhere this same cycle (e.g. as its own top-level card, if its
    // actual parent is filtered out of the active list) can have that
    // field re-stamped by other code before this reads it.
    property int depth: taskData.depth || 0
    // Stamped by main.qml's orderTasksWithHierarchy: childCount counts
    // every descendant (not just direct subtasks) a collapsed task hides;
    // collapsed reflects the persisted per-task fold state. Both are only
    // meaningful (childCount > 0) on a task that actually has subtasks.
    readonly property int childCount: taskData.childCount || 0
    readonly property bool collapsed: !!taskData.collapsed
    // Set by main.qml's "Recently completed" section only - there, a
    // completed task's own due date isn't why it's in that list, when it
    // was finished is, so its row shows that instead of (or alongside)
    // any due date, the same way every other completed task in that
    // section does.
    property bool showCompletedDate: false

    implicitHeight: row.implicitHeight + Kirigami.Units.mediumSpacing * 2

    HoverHandler {
        id: hover
    }

    Rectangle {
        // A light highlight only, not a full card background - the card's
        // own background (see TaskFamilyCard.qml) already covers the
        // whole family, so this row doesn't need one of its own.
        anchors.fill: parent
        visible: hover.hovered
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.hoverColor
        // Sits on top of the card's own (now already-hovered) background -
        // see TaskFamilyCard.qml - so this only needs to be a faint extra
        // tint pointing at the specific row under the pointer, not another
        // full-strength layer of hoverColor stacked on top of that one.
        opacity: 0.25
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.mediumSpacing + Kirigami.Units.smallSpacing * 0.6 + Kirigami.Units.smallSpacing +
                             delegate.depth * Kirigami.Units.gridUnit
        anchors.rightMargin: Kirigami.Units.mediumSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.CheckBox {
            id: completeCheck
            checked: delegate.completed
            onToggled: delegate.toggled()
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                // The calendar-color accent bar already identifies which
                // calendar this is, the same way it does for events - a
                // separate calendar-name line was redundant.
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.strikeout: delegate.completed || delegate.cancelled
                font.pointSize: delegate.depth > 0 ? Kirigami.Theme.smallFont.pointSize : Kirigami.Theme.defaultFont.pointSize
                opacity: (delegate.completed || delegate.cancelled) ? 0.6 : 1
                // See EventDelegate.qml's summary Label for why this must be
                // plain text: this renders a server-supplied task summary.
                textFormat: Text.PlainText
                text: delegate.taskData.summary || i18n("(No title)")
            }

            // Cancelled/in-progress and completed-with-date are mutually
            // exclusive (a task only ever has one status), so only one of
            // these two ever shows at once.
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: delegate.inProgress || delegate.cancelled
                elide: Text.ElideRight
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: delegate.inProgress ? i18n("In progress (%1%)", delegate.taskData.percentComplete || 0) : i18n("Cancelled")
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: delegate.showCompletedDate && delegate.completed && !!delegate.taskData.completed
                elide: Text.ElideRight
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: visible ? i18n("Completed %1", delegate.formatCompletedDate(delegate.taskData.completed)) : ""
            }
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
            // Pinned to the checkbox's own natural height, not this
            // ToolButton's own (taller) implicit size or some separately
            // guessed constant - the checkbox is always present, so this
            // guarantees the button can never exceed the row's own
            // already-established baseline height, whatever that
            // actually is on this theme. Otherwise the row's height - and
            // every other row's position below it - grows the moment this
            // button appears on hover, then shrinks back when it leaves,
            // visibly jumping.
            Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
            Layout.preferredHeight: completeCheck.implicitHeight
            icon.name: "list-add"
            onClicked: delegate.addSubtaskRequested()
            PlasmaComponents3.ToolTip.text: i18n("Add subtask…")
            PlasmaComponents3.ToolTip.visible: hovered
        }

        PlasmaComponents3.ToolButton {
            visible: hover.hovered
            // See the add-subtask button above for why.
            Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
            Layout.preferredHeight: completeCheck.implicitHeight
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

    function formatCompletedDate(d) {
        return Qt.formatDate(d, "d MMM") + ", " +
               Qt.formatTime(d, plasmoid.configuration.use24HourClock ? "HH:mm" : "h:mm AP");
    }
}
