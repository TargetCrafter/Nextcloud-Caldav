import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    id: delegate

    required property var eventData

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.smallSpacing
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    Rectangle {
        Layout.preferredWidth: Kirigami.Units.smallSpacing / 2
        Layout.fillHeight: true
        Layout.topMargin: 2
        Layout.bottomMargin: 2
        radius: width / 2
        color: delegate.eventData.calendarColor || Kirigami.Theme.highlightColor
    }

    PlasmaComponents3.Label {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.2
        horizontalAlignment: Text.AlignRight
        opacity: 0.8
        text: delegate.eventData.allDay ? i18n("All day")
              : Qt.formatTime(delegate.eventData.dtstart, plasmoid.configuration.use24HourClock ? "HH:mm" : "h:mm AP")
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: delegate.eventData.summary || i18n("(No title)")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: plasmoid.configuration.showEventLocation && delegate.eventData.location !== ""
            elide: Text.ElideRight
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: delegate.eventData.location
        }
    }
}
