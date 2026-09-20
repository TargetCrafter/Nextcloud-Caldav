import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// A task and everything that visually belongs to it - its active
// subtasks, and its own "Completed" subtask heading + rows - as one
// card: one shared background, one shared accent bar spanning the card's
// full height, and a plain Column (not a Layout - a Layout combined with
// a Repeater is what broke the very first attempt at this) stacking each
// row's own content. A leaf task with no subtasks/closed rows is just a
// one-row card.
//
// Replaces the earlier approach of giving every row (task, subtask,
// "Completed" heading) its own independent accent bar and trying to
// make them line up pixel-perfect with their neighbors to read as one
// continuous line - which left visible gaps (and, since a row's height
// could differ from its neighbor's, bars of inconsistent length) across
// three separate attempts to fix it. With one bar drawn once for the
// whole family, there's nothing left to line up.
Item {
    id: card

    required property var root
    // [{ kind: "task", data } | { kind: "closedHeader", label, count, depth, color }],
    // in visual order - see main.qml's orderTasksWithHierarchy.
    property var rows: []
    // Set only by main.qml's "Recently completed" section - see
    // TaskRow.qml's own showCompletedDate for what this does.
    property bool showCompletedDate: false

    signal toggled(var task)
    signal editRequested(var task)
    signal addSubtaskRequested(var task)
    signal toggleCollapseRequested(string uid)

    implicitHeight: column.implicitHeight

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        // Matches EventDelegate's card background - the calendar-color
        // accent bar below is what now tells tasks and events apart, the
        // same way it already does between different calendars. Hovered
        // opacity is well short of 1 - Theme.hoverColor at full strength
        // was saturated enough to make the row's own text hard to read
        // against it.
        color: hover.hovered ? Kirigami.Theme.hoverColor : Kirigami.Theme.alternateBackgroundColor
        opacity: hover.hovered ? 0.5 : 0.35
    }

    // The one bar for this whole family - spans the card's full height, so
    // a task with subtasks (and/or its own recently-closed subtask rows)
    // reads as a single continuous colored line, not a chain of separate
    // segments.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Kirigami.Units.mediumSpacing
        width: Kirigami.Units.smallSpacing * 0.6
        radius: width / 2
        color: card.root.calendarColor || Kirigami.Theme.highlightColor
    }

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        TaskRow {
            width: column.width
            taskData: card.root
            showCompletedDate: card.showCompletedDate
            onToggled: card.toggled(card.root)
            onEditRequested: card.editRequested(card.root)
            onAddSubtaskRequested: card.addSubtaskRequested(card.root)
            onToggleCollapseRequested: card.toggleCollapseRequested(card.root.uid)
        }

        Repeater {
            model: card.rows

            delegate: Loader {
                width: column.width
                property var rowData: modelData
                sourceComponent: rowData.kind === "closedHeader" ? closedHeaderRowComponent : taskRowComponent
            }
        }
    }

    Component {
        id: taskRowComponent
        TaskRow {
            taskData: parent.rowData.data
            showCompletedDate: card.showCompletedDate
            onToggled: card.toggled(parent.rowData.data)
            onEditRequested: card.editRequested(parent.rowData.data)
            onAddSubtaskRequested: card.addSubtaskRequested(parent.rowData.data)
            onToggleCollapseRequested: card.toggleCollapseRequested(parent.rowData.data.uid)
        }
    }

    Component {
        id: closedHeaderRowComponent
        Item {
            id: header
            // Bound once, here, at the root of this component - so every
            // binding below can go through this id instead of each
            // reaching for `parent.rowData` again at a different nesting
            // depth, where `parent` would no longer mean the Loader above.
            property var rowData: parent.rowData

            implicitHeight: label.implicitHeight + Kirigami.Units.smallSpacing * 2

            PlasmaComponents3.Label {
                id: label
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Kirigami.Units.mediumSpacing + Kirigami.Units.smallSpacing * 0.6 + Kirigami.Units.smallSpacing +
                                     header.rowData.depth * Kirigami.Units.gridUnit
                anchors.rightMargin: Kirigami.Units.mediumSpacing
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
                text: i18np("Completed (%1)", "Completed (%1)", header.rowData.count)
            }
        }
    }
}
