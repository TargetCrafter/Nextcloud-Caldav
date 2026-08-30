import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/dateutils.js" as DateUtils

Item {
    id: compact

    property var nextEvent: null
    property int todayCount: 0
    property int overdueCount: 0
    property bool isLoading: false
    property string lastError: ""

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool showLabel: !vertical && Plasmoid.formFactor !== PlasmaCore.Types.Planar &&
                                       plasmoid.configuration.compactMode !== 2 /* IconOnly */

    Layout.minimumWidth: showLabel ? layout.implicitWidth + Kirigami.Units.smallSpacing * 2 : height
    Layout.minimumHeight: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            id: icon
            source: overdueCount > 0 ? "task-attention" : "view-calendar"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small

            PlasmaComponents3.BusyIndicator {
                anchors.fill: parent
                running: compact.isLoading
                visible: running
            }
        }

        PlasmaComponents3.Label {
            visible: compact.showLabel
            Layout.fillWidth: false
            elide: Text.ElideRight
            text: compact.labelText()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: plasmoid.expanded = !plasmoid.expanded
    }

    function labelText() {
        if (lastError !== "" && lastError !== "unconfigured") return i18n("Error");
        if (lastError === "unconfigured") return i18n("Not set up");

        var mode = plasmoid.configuration.compactMode;
        if (mode === 1 /* TodayCount */) {
            return i18np("%1 event today", "%1 events today", todayCount);
        }
        if (mode === 2 /* IconOnly */) return "";

        if (!nextEvent) return i18n("No upcoming events");
        if (nextEvent.allDay) return nextEvent.summary;

        var mins = DateUtils.minutesUntil(nextEvent.dtstart);
        var when;
        if (mins <= 0) when = i18n("now");
        else if (mins < 60) when = i18np("in %1 min", "in %1 min", Math.round(mins));
        else if (mins < 24 * 60) when = i18np("in %1 hr", "in %1 hr", Math.round(mins / 60));
        else when = i18np("in %1 day", "in %1 days", Math.round(mins / (60 * 24)));
        return i18n("%1: %2", when, nextEvent.summary);
    }
}
