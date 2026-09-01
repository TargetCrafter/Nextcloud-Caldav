import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: delegate

    required property var eventData

    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 1.6

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Kirigami.Units.cornerRadius
        color: hover.hovered ? Kirigami.Theme.hoverColor : Kirigami.Theme.backgroundColor
        opacity: hover.hovered ? 1 : 0.4
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.smallSpacing * 0.6
            Layout.fillHeight: true
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
}
