import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: delegate

    required property var eventData
    // Ticks once a minute (see main.qml's clockTimer), so isPast below
    // stays live rather than being frozen at whatever it was at the last
    // refresh - which could be up to refreshInterval minutes (as long as 4
    // hours) stale otherwise.
    property date currentTime

    signal editRequested()

    // An event that has already ended (or, for a point-in-time event with
    // no end, already started) earlier today.
    readonly property bool isPast: {
        var end = eventData.dtend || eventData.dtstart;
        return !!end && end.getTime() < currentTime.getTime();
    }

    // Match the row's own top/bottom inset (see anchors.margins below)
    // exactly, so the card's implicit height doesn't drift from the row's
    // natural content height - a mismatch there left the RowLayout taller
    // than its content and pushed the extra slack unevenly to one side.
    implicitHeight: row.implicitHeight + Kirigami.Units.mediumSpacing * 2

    opacity: isPast ? 0.5 : 1

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        color: hover.hovered ? Kirigami.Theme.hoverColor : Kirigami.Theme.alternateBackgroundColor
        opacity: hover.hovered ? 1 : 0.35
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Kirigami.Units.mediumSpacing
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

        PlasmaComponents3.ToolButton {
            // Recurring events aren't editable/deletable here - which
            // occurrence(s) an edit should apply to is a real feature of
            // its own, not something to guess at with a single-resource
            // PUT/DELETE.
            visible: hover.hovered && !delegate.eventData.isRecurring
            icon.name: "document-edit"
            onClicked: delegate.editRequested()
            PlasmaComponents3.ToolTip.text: i18n("Edit…")
            PlasmaComponents3.ToolTip.visible: hovered
        }
    }
}
