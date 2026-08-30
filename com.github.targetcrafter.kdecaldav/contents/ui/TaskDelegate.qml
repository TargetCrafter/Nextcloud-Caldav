import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    id: delegate

    required property var taskData
    signal toggled()

    readonly property bool completed: taskData.status === "COMPLETED"

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.smallSpacing
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

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
