import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Wraps a top-level task and its rendered descendants (active subtasks,
// plus that task's own recently completed subtasks - see
// closedSubtasksByParent/groupTaskFamilies in main.qml) in a single
// delegate, so the whole family shares ONE calendar-color accent bar
// spanning its full height, instead of each row drawing its own short
// segment that only looks continuous when every row happens to share the
// same color. Used whenever a top-level task has anything to show under
// it (childCount > 0 and not collapsed) - see FullRepresentation.qml's
// Loader switch; a task with nothing under it, or a collapsed one, still
// renders as a plain TaskDelegate instead.
//
// The shared bar here is drawn at exactly the position/size a standalone
// TaskDelegate's own (hidden via showAccentBar: false) bar would use, so
// each embedded row's content lines up pixel-for-pixel with a plain,
// non-grouped row - see TaskDelegate.qml's own comment on that margin.
Item {
    id: group

    required property var groupData // { root, children: [...] }

    signal toggled(var task)
    signal editRequested(var task)
    signal addSubtaskRequested(var task)
    signal toggleCollapseRequested(string uid)

    implicitHeight: column.implicitHeight

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Kirigami.Units.mediumSpacing
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        width: Kirigami.Units.smallSpacing * 0.6
        radius: width / 2
        color: group.groupData.root.calendarColor || Kirigami.Theme.highlightColor
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        TaskDelegate {
            Layout.fillWidth: true
            taskData: group.groupData.root
            showAccentBar: false
            onToggled: group.toggled(group.groupData.root)
            onEditRequested: group.editRequested(group.groupData.root)
            onAddSubtaskRequested: group.addSubtaskRequested(group.groupData.root)
            onToggleCollapseRequested: group.toggleCollapseRequested(group.groupData.root.uid)
        }

        Repeater {
            model: group.groupData.children
            delegate: TaskDelegate {
                Layout.fillWidth: true
                taskData: modelData
                showAccentBar: false
                onToggled: group.toggled(modelData)
                onEditRequested: group.editRequested(modelData)
                onAddSubtaskRequested: group.addSubtaskRequested(modelData)
                onToggleCollapseRequested: group.toggleCollapseRequested(modelData.uid)
            }
        }
    }
}
