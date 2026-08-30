import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/caldav.js" as CalDAV

Kirigami.FormLayout {
    id: page

    property alias cfg_serverUrl: serverUrlField.text
    property alias cfg_username: usernameField.text
    property alias cfg_appPassword: passwordField.text

    property bool discovering: false
    property string discoverError: ""
    property var discovered: []

    QQC2.TextField {
        id: serverUrlField
        Kirigami.FormData.label: i18n("Server address:")
        placeholderText: i18n("https://cloud.example.com")
        onTextChanged: { page.discovered = []; page.discoverError = ""; }
    }

    QQC2.TextField {
        id: usernameField
        Kirigami.FormData.label: i18n("Username:")
        onTextChanged: { page.discovered = []; page.discoverError = ""; }
    }

    Kirigami.PasswordField {
        id: passwordField
        Kirigami.FormData.label: i18n("App password:")
        onTextChanged: { page.discovered = []; page.discoverError = ""; }
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.75
        text: i18n("Use an app password, not your account password: Nextcloud → Settings → Security → Devices & sessions → Create new app password.")
    }

    RowLayout {
        Kirigami.FormData.label: " "
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            text: i18n("Find calendars")
            icon.name: "cloud-download"
            enabled: serverUrlField.text.length > 0 && usernameField.text.length > 0 && passwordField.text.length > 0 && !page.discovering
            onClicked: page.discover()
        }

        PlasmaComponents3.BusyIndicator {
            running: page.discovering
            visible: running
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
        }

        QQC2.Label {
            visible: page.discoverError !== ""
            color: Kirigami.Theme.negativeTextColor
            text: page.discoverError
        }
    }

    ColumnLayout {
        Kirigami.FormData.label: i18n("Calendars:")
        visible: page.discovered.length > 0
        Layout.fillWidth: true
        spacing: 0

        Repeater {
            model: page.discovered
            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.CheckBox {
                    checked: page.isEnabled(modelData.href)
                    onToggled: page.setCalendarEnabled(modelData.href, checked)
                }

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium * 0.35
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: width / 2
                    color: modelData.color || "#3daee9"
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: modelData.displayName
                }

                QQC2.Label {
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: modelData.kinds.indexOf("VTODO") !== -1 && modelData.kinds.indexOf("VEVENT") === -1
                          ? i18n("tasks") : (modelData.kinds.indexOf("VTODO") !== -1 ? i18n("events + tasks") : i18n("events"))
                }
            }
        }
    }

    function discover() {
        discovering = true;
        discoverError = "";
        CalDAV.discoverCalendars(serverUrlField.text, usernameField.text, passwordField.text, function (err, calendars) {
            discovering = false;
            if (err) {
                discoverError = err === "auth" ? i18n("Sign-in failed. Check the username and app password.")
                              : err === "notfound" ? i18n("Server address not found.")
                              : err === "network" ? i18n("Couldn't reach the server.")
                              : i18n("Something went wrong (%1).", err);
                return;
            }
            if (calendars.length === 0) {
                discoverError = i18n("No calendars found for this account.");
                return;
            }
            var firstRun = plasmoid.configuration.enabledCalendarUrls.length === 0;
            calendars.forEach(function (cal) {
                upsertCalendarMeta(cal);
                if (firstRun) setCalendarEnabled(cal.href, true);
            });
            discovered = calendars;
        });
    }

    function isEnabled(href) {
        return plasmoid.configuration.enabledCalendarUrls.indexOf(href) !== -1;
    }

    function upsertCalendarMeta(cal) {
        var urls = plasmoid.configuration.calendarUrls.slice();
        var names = plasmoid.configuration.calendarNames.slice();
        var colors = plasmoid.configuration.calendarColors.slice();
        var kinds = plasmoid.configuration.calendarKinds.slice();
        var kindsStr = cal.kinds.join(",");
        var idx = urls.indexOf(cal.href);
        if (idx === -1) {
            urls.push(cal.href);
            names.push(cal.displayName);
            colors.push(cal.color || "#3daee9");
            kinds.push(kindsStr);
        } else {
            names[idx] = cal.displayName;
            colors[idx] = cal.color || colors[idx];
            kinds[idx] = kindsStr;
        }
        plasmoid.configuration.calendarUrls = urls;
        plasmoid.configuration.calendarNames = names;
        plasmoid.configuration.calendarColors = colors;
        plasmoid.configuration.calendarKinds = kinds;
    }

    function setCalendarEnabled(href, enabled) {
        var list = plasmoid.configuration.enabledCalendarUrls.slice();
        var idx = list.indexOf(href);
        if (enabled && idx === -1) list.push(href);
        if (!enabled && idx !== -1) list.splice(idx, 1);
        plasmoid.configuration.enabledCalendarUrls = list;
    }

    Component.onCompleted: {
        // Pre-populate the list from calendars already known from a previous
        // discovery, so re-opening settings still shows current selections.
        var urls = plasmoid.configuration.calendarUrls;
        var names = plasmoid.configuration.calendarNames;
        var colors = plasmoid.configuration.calendarColors;
        var kinds = plasmoid.configuration.calendarKinds;
        var out = [];
        for (var i = 0; i < urls.length; i++) {
            out.push({ href: urls[i], displayName: names[i], color: colors[i], kinds: (kinds[i] || "VEVENT").split(",") });
        }
        discovered = out;
    }
}
