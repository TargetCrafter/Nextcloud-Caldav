import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: delegate

    required property var taskData
    signal toggled()

    readonly property bool completed: taskData.status === "COMPLETED"
    readonly property int depth: taskData.depth || 0

    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 1.6

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Kirigami.Units.cornerRadius
        // Tasks get a faint tint (as opposed to events' plain background) so
        // the two kinds of agenda item are distinguishable at a glance even
        // before reading their content.
        color: hover.hovered ? Kirigami.Theme.hoverColor : Kirigami.Theme.neutralBackgroundColor
        opacity: hover.hovered ? 1 : 0.25
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        anchors.leftMargin: Kirigami.Units.smallSpacing + delegate.depth * Kirigami.Units.gridUnit
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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.strikeout: delegate.completed
                font.pointSize: delegate.depth > 0 ? Kirigami.Theme.smallFont.pointSize : Kirigami.Theme.defaultFont.pointSize
                opacity: delegate.completed ? 0.6 : 1
                text: delegate.taskData.summary || i18n("(No title)")
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text !== ""
                elide: Text.ElideRight
                opacity: 0.7
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: delegate.taskData.calendarName || ""
            }
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
