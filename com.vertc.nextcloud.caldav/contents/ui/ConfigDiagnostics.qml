import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Read-only view of main.qml's logWarn output (see main.xml's
// "diagnosticLog" entry). This page runs in the config dialog's own
// separate QML engine, like every Config*.qml page - there's no live
// connection to the running widget's JS state from here, so the log has
// to be persisted to config for this to be able to show it at all.
QQC2.ScrollView {
    id: page

    property alias cfg_diagnosticLog: logArea.text

    ColumnLayout {
        width: page.width
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            wrapMode: Text.WordWrap
            opacity: 0.75
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: i18n("The most recent errors this widget has run into - failing to fetch, save, or delete something - newest first. Worth including when reporting a problem. Nothing sensitive like your password is ever logged here.")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: logArea.text.trim() === ""
            opacity: 0.6
            text: i18n("No errors logged yet.")
        }

        QQC2.TextArea {
            id: logArea
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.preferredHeight: Kirigami.Units.gridUnit * 16
            visible: text.trim() !== ""
            readOnly: true
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }

        RowLayout {
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Copy to Clipboard")
                icon.name: "edit-copy"
                enabled: logArea.text.trim() !== ""
                onClicked: {
                    logArea.selectAll();
                    logArea.copy();
                    logArea.deselect();
                }
            }

            QQC2.Button {
                text: i18n("Clear")
                icon.name: "edit-clear-all"
                enabled: logArea.text.trim() !== ""
                onClicked: logArea.text = ""
            }
        }
    }
}
