import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/dateutils.js" as DateUtils

RowLayout {
    id: header

    // Either `date` (a day grouping header) or `label`+`count` (a named
    // section like "Overdue" / "No due date") is set, not both.
    property date date
    property string label: ""
    property int count: 0

    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    Layout.bottomMargin: Kirigami.Units.smallSpacing / 2
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        visible: header.label === "overdue"
        source: "task-attention"
        color: Kirigami.Theme.negativeTextColor
        Layout.preferredWidth: Kirigami.Units.iconSizes.small
        Layout.preferredHeight: Kirigami.Units.iconSizes.small
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        color: header.label === "overdue" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        text: header.text()
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        opacity: 0.5
    }

    function text() {
        if (label === "overdue") return i18np("Overdue (%1)", "Overdue (%1)", count);
        if (label === "noDueDate") return i18n("No due date");

        var offset = DateUtils.dayOffset(date);
        if (offset === 0) return i18n("Today · %1", Qt.formatDate(date, "d MMMM"));
        if (offset === 1) return i18n("Tomorrow · %1", Qt.formatDate(date, "d MMMM"));
        return Qt.formatDate(date, "dddd · d MMMM");
    }
}
