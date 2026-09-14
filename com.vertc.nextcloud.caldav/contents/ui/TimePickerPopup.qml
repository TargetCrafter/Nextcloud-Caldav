import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Small reusable hour/minute time picker, opened from ItemFormPopup's time
// field. Mirrors DatePickerPopup.qml's structure/positioning for visual and
// behavioral consistency.
QQC2.Popup {
    id: picker

    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    width: Kirigami.Units.gridUnit * 14

    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0

    background: Rectangle {
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Kirigami.Theme.highlightColor
    }

    signal picked(int hours, int minutes)

    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }

    // Opens with the spin boxes set to `hours`/`minutes` (or the current
    // time if either is unset/NaN).
    function openFor(hours, minutes) {
        var now = new Date();
        hourSpin.value = (hours !== undefined && !isNaN(hours)) ? hours : now.getHours();
        minuteSpin.value = (minutes !== undefined && !isNaN(minutes)) ? minutes : now.getMinutes();
        picker.open();
    }

    ColumnLayout {
        width: picker.availableWidth
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            level: 4
            text: i18n("Set time")
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: hourSpin
                from: 0
                to: 23
                editable: true
                textFromValue: (value) => picker.pad2(value)
                valueFromText: (text) => parseInt(text, 10) || 0
            }
            QQC2.Label {
                text: ":"
                font.bold: true
            }
            QQC2.SpinBox {
                id: minuteSpin
                from: 0
                to: 59
                editable: true
                textFromValue: (value) => picker.pad2(value)
                valueFromText: (text) => parseInt(text, 10) || 0
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                Layout.fillWidth: true
                flat: true
                text: i18n("Now")
                onClicked: {
                    var now = new Date();
                    picker.picked(now.getHours(), now.getMinutes());
                    picker.close();
                }
            }
            QQC2.Button {
                Layout.fillWidth: true
                text: i18n("Set")
                onClicked: {
                    picker.picked(hourSpin.value, minuteSpin.value);
                    picker.close();
                }
            }
        }
    }
}
