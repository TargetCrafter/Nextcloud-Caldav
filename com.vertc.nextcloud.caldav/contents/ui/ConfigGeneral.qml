import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/caldav.js" as CalDAV

// A plain ScrollView (rather than the FormLayout below being the root
// item directly, as it used to be) so this page scrolls internally once
// its content - e.g. several calendars with their filter box open at
// once - is taller than the config window. The standalone "Configure…"
// window this loads into doesn't add any scrolling of its own: without
// this, taller-than-the-window content (like a calendar's filter editor)
// pushed the OK/Apply/Cancel buttons and everything below it out of reach
// entirely, with no way to get to them.
QQC2.ScrollView {
    id: page

    property alias cfg_serverUrl: serverUrlField.text
    property alias cfg_username: usernameField.text
    property alias cfg_appPassword: passwordField.text

    // idle | requesting | waiting | success | error
    property string loginState: "idle"
    property string loginError: ""
    property string loginPollToken: ""
    property string loginPollEndpoint: ""
    property real loginDeadline: 0

    property bool showManualFields: false

    property bool discovering: false
    property string discoverError: ""
    property var discovered: []

    // "Add/Edit calendar by URL" form state. icsEditingHref is the href of
    // the calendar currently being edited (see startEditIcsCalendar),
    // empty when the form is in "add a new one" mode instead.
    property color icsColor: "#3daee9"
    property string icsAddError: ""
    property string icsEditingHref: ""

    Kirigami.FormLayout {
        width: page.width

    QQC2.TextField {
        id: serverUrlField
        Kirigami.FormData.label: i18n("Server address:")
        placeholderText: i18n("https://cloud.example.com")
        enabled: page.loginState !== "waiting" && page.loginState !== "requesting"
        onTextChanged: {
            page.discovered = [];
            page.discoverError = "";
            if (page.loginState === "success" || page.loginState === "error") page.loginState = "idle";
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: /^http:\/\//i.test(serverUrlField.text.trim())
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        color: Kirigami.Theme.neutralTextColor
        text: i18n("This address uses unencrypted http://. Your username and app password will be sent in the clear unless this server is only reachable over a trusted network.")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Account:")
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            text: i18n("Log in with Nextcloud…")
            icon.name: "internet-services"
            enabled: serverUrlField.text.length > 0 && page.loginState !== "waiting" && page.loginState !== "requesting"
            onClicked: page.startLogin()
        }

        PlasmaComponents3.BusyIndicator {
            running: page.loginState === "requesting" || page.loginState === "waiting"
            visible: running
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
        }

        QQC2.Button {
            text: i18n("Cancel")
            visible: page.loginState === "waiting"
            onClicked: page.cancelLogin()
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: page.loginState === "waiting"
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        text: i18n("Finish signing in in the browser window that just opened, then come back here.")
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: page.loginState === "success"
        color: Kirigami.Theme.positiveTextColor
        // usernameField.text here comes from the server's login-flow
        // response (result.loginName), not local input.
        textFormat: Text.PlainText
        text: i18n("Signed in as %1.", usernameField.text)
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: page.loginState === "error"
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        text: page.loginError
    }

    QQC2.Button {
        Kirigami.FormData.label: " "
        flat: true
        visible: !page.showManualFields
        text: i18n("Sign in manually instead…")
        onClicked: page.showManualFields = true
    }

    QQC2.TextField {
        id: usernameField
        Kirigami.FormData.label: i18n("Username:")
        visible: page.showManualFields
        onTextChanged: { page.discovered = []; page.discoverError = ""; }
    }

    Kirigami.PasswordField {
        id: passwordField
        Kirigami.FormData.label: i18n("App password:")
        visible: page.showManualFields
        onTextChanged: { page.discovered = []; page.discoverError = ""; }
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: page.showManualFields
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.75
        text: i18n("Only needed if browser sign-in isn't available. Use an app password, not your account password: Nextcloud → Settings → Security → Devices & sessions → Create new app password.")
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Calendars:")
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
        Kirigami.FormData.label: " "
        visible: page.discovered.length > 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: page.discovered
            delegate: ColumnLayout {
                id: calRow
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                property bool filtersOpen: false

                RowLayout {
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
                        border.width: modelData.source === "ics" ? 1 : 0
                        border.color: Kirigami.Theme.disabledTextColor

                        // Only a calendar added by URL can have its color
                        // edited here - a CalDAV calendar's color comes
                        // from the server (calendar-color), and re-running
                        // "Find calendars" would just overwrite a locally
                        // edited one back anyway.
                        MouseArea {
                            anchors.fill: parent
                            visible: modelData.source === "ics"
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                editColorDialog.targetHref = modelData.href;
                                editColorDialog.selectedColor = modelData.color || "#3daee9";
                                editColorDialog.open();
                            }
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        // See EventDelegate.qml's summary Label for why
                        // this must be plain text: this renders a
                        // server-supplied calendar display name discovered
                        // via PROPFIND (or a user-entered one, for a
                        // calendar added by URL).
                        textFormat: Text.PlainText
                        text: modelData.displayName
                    }

                    QQC2.Label {
                        opacity: 0.6
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: modelData.kinds.indexOf("VTODO") !== -1 && modelData.kinds.indexOf("VEVENT") === -1
                              ? i18n("tasks") : (modelData.kinds.indexOf("VTODO") !== -1 ? i18n("events + tasks") : i18n("events"))
                    }

                    QQC2.Button {
                        flat: true
                        text: {
                            if (calRow.filtersOpen) return i18n("Hide filter");
                            var inCount = page.filterCount(modelData.filtersText);
                            var outCount = page.filterCount(modelData.excludeFiltersText);
                            if (inCount === 0 && outCount === 0) return i18n("Filter…");
                            return i18n("Filter (%1 in, %2 out)", inCount, outCount);
                        }
                        onClicked: calRow.filtersOpen = !calRow.filtersOpen
                    }

                    QQC2.ToolButton {
                        visible: modelData.source === "ics"
                        icon.name: "document-edit"
                        onClicked: page.startEditIcsCalendar(modelData)
                        PlasmaComponents3.ToolTip.text: i18n("Edit URL, name, or color…")
                        PlasmaComponents3.ToolTip.visible: hovered
                    }

                    QQC2.ToolButton {
                        visible: modelData.source === "ics"
                        icon.name: "edit-delete"
                        onClicked: page.removeCalendar(modelData.href)
                        PlasmaComponents3.ToolTip.text: i18n("Remove this calendar")
                        PlasmaComponents3.ToolTip.visible: hovered
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    visible: calRow.filtersOpen
                    spacing: Kirigami.Units.smallSpacing / 2

                    QQC2.Label {
                        opacity: 0.7
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: i18n("Only show if title contains (one per line, optional):")
                    }

                    // Its own small ScrollView with a fixed height, rather
                    // than just growing with content, so a filter list with
                    // many lines can't blow up the page's height either -
                    // it scrolls internally instead.
                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                        clip: true

                        QQC2.TextArea {
                            placeholderText: i18n("e.g. - Race")
                            text: modelData.filtersText
                            wrapMode: TextEdit.Wrap
                            onEditingFinished: page.setCalendarFilters(modelData.href, text)
                        }
                    }

                    QQC2.Label {
                        opacity: 0.7
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: i18n("Hide if title contains (one per line, optional):")
                    }

                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                        clip: true

                        QQC2.TextArea {
                            placeholderText: i18n("e.g. Sprint Shootout")
                            text: modelData.excludeFiltersText
                            wrapMode: TextEdit.Wrap
                            onEditingFinished: page.setCalendarExcludeFilters(modelData.href, text)
                        }
                    }
                }
            }
        }
    }

    ColorDialog {
        id: editColorDialog
        property string targetHref: ""
        onAccepted: page.setCalendarColor(targetHref, selectedColor)
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

    RowLayout {
        Kirigami.FormData.label: page.icsEditingHref !== "" ? i18n("Edit calendar URL:") : i18n("Add calendar by URL:")
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: icsUrlField
            Layout.fillWidth: true
            placeholderText: i18n("webcal://... or https://.../calendar.ics")
            onTextChanged: page.icsAddError = ""
        }
    }

    RowLayout {
        Kirigami.FormData.label: " "
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: icsNameField
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
            placeholderText: i18n("Name")
        }

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: page.icsColor
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    addColorDialog.selectedColor = page.icsColor;
                    addColorDialog.open();
                }
            }
        }

        QQC2.Button {
            text: page.icsEditingHref !== "" ? i18n("Save") : i18n("Add")
            enabled: icsUrlField.text.trim().length > 0
            onClicked: page.saveIcsCalendar()
        }

        QQC2.Button {
            text: i18n("Cancel")
            visible: page.icsEditingHref !== ""
            onClicked: page.cancelIcsEdit()
        }
    }

    ColorDialog {
        id: addColorDialog
        onAccepted: page.icsColor = selectedColor
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        visible: page.icsAddError !== ""
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        text: page.icsAddError
    }

    QQC2.Label {
        Kirigami.FormData.label: " "
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.75
        text: i18n("For a plain .ics feed (a subscription link, not your Nextcloud account) - fetched read-only and unauthenticated, so don't use this for anything private that needs a login.")
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        onTriggered: page.pollLogin()
    }

    } // Kirigami.FormLayout

    function startLogin() {
        loginState = "requesting";
        loginError = "";
        CalDAV.startLoginFlow(serverUrlField.text, function (err, data) {
            if (err) {
                page.loginState = "error";
                page.loginError = page.describeLoginError(err);
                return;
            }
            // data.login is server-supplied; only open it if it's actually
            // an http(s) URL rather than handing some other URI scheme
            // (which could trigger an arbitrary registered handler) to
            // openUrlExternally sight unseen.
            if (!/^https?:\/\//i.test(data.login)) {
                page.loginState = "error";
                page.loginError = page.describeLoginError("parse");
                return;
            }
            page.loginPollToken = data.poll.token;
            page.loginPollEndpoint = data.poll.endpoint;
            page.loginDeadline = Date.now() + 10 * 60 * 1000;
            Qt.openUrlExternally(data.login);
            page.loginState = "waiting";
            pollTimer.start();
        });
    }

    function pollLogin() {
        if (Date.now() > loginDeadline) {
            pollTimer.stop();
            page.loginState = "error";
            page.loginError = i18n("Sign-in timed out. Try again.");
            return;
        }
        CalDAV.pollLoginFlow(loginPollEndpoint, loginPollToken, function (err, result) {
            if (!err) {
                pollTimer.stop();
                usernameField.text = result.loginName;
                passwordField.text = result.appPassword;
                if (result.server) serverUrlField.text = result.server;
                page.loginState = "success";
                page.discover();
            } else if (err !== "pending") {
                pollTimer.stop();
                page.loginState = "error";
                page.loginError = page.describeLoginError(err);
            }
        });
    }

    function cancelLogin() {
        pollTimer.stop();
        loginState = "idle";
    }

    function describeLoginError(code) {
        switch (code) {
        case "notfound": return i18n("Login flow not found on this server. Update Nextcloud, or sign in manually.");
        case "network": return i18n("Couldn't reach the server.");
        case "auth": return i18n("The server refused the request.");
        default: return i18n("Something went wrong (%1). Try again, or sign in manually.", code);
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
            rebuildDiscoveredFromConfig();
        });
    }

    function isEnabled(href) {
        return plasmoid.configuration.enabledCalendarUrls.indexOf(href) !== -1;
    }

    // calendarSources/calendarFilters are newer than
    // calendarUrls/Names/Colors/Kinds, so on an upgrade (or right after
    // adding a brand-new calendar mid-session) they can be shorter than
    // those - pads with a harmless default so a later push() lands at the
    // right index instead of silently misaligning every array from here on.
    function padTo(list, length, fill) {
        while (list.length < length) list.push(fill);
        return list;
    }

    function upsertCalendarMeta(cal) {
        var urls = plasmoid.configuration.calendarUrls.slice();
        var names = plasmoid.configuration.calendarNames.slice();
        var colors = plasmoid.configuration.calendarColors.slice();
        var kinds = plasmoid.configuration.calendarKinds.slice();
        var sources = plasmoid.configuration.calendarSources.slice();
        var filtersList = plasmoid.configuration.calendarFilters.slice();
        var excludeFiltersList = plasmoid.configuration.calendarExcludeFilters.slice();
        // "+" rather than "," on purpose: calendarKinds is itself a
        // KConfigXT StringList, whose own on-disk serialization already
        // uses "," as the separator *between* list entries, so joining a
        // per-calendar kind set with "," here would collide with that and
        // corrupt the parallel calendarUrls/calendarNames/.../calendarKinds
        // arrays' index alignment for any calendar supporting more than
        // one component type (i.e. most normal calendars, which are both
        // VEVENT and VTODO capable).
        var kindsStr = cal.kinds.join("+");
        var idx = urls.indexOf(cal.href);
        if (idx === -1) {
            padTo(sources, urls.length, "caldav");
            padTo(filtersList, urls.length, "");
            padTo(excludeFiltersList, urls.length, "");
            urls.push(cal.href);
            names.push(cal.displayName);
            colors.push(cal.color || "#3daee9");
            kinds.push(kindsStr);
            sources.push("caldav");
            filtersList.push("");
            excludeFiltersList.push("");
        } else {
            names[idx] = cal.displayName;
            colors[idx] = cal.color || colors[idx];
            kinds[idx] = kindsStr;
            // sources[idx]/filtersList[idx]/excludeFiltersList[idx]
            // deliberately left alone - re-discovering a calendar that's
            // already known (the normal case on every "Find calendars"
            // click) must not reset a calendar's own source or clear
            // filters the user already set.
        }
        plasmoid.configuration.calendarUrls = urls;
        plasmoid.configuration.calendarNames = names;
        plasmoid.configuration.calendarColors = colors;
        plasmoid.configuration.calendarKinds = kinds;
        plasmoid.configuration.calendarSources = sources;
        plasmoid.configuration.calendarFilters = filtersList;
        plasmoid.configuration.calendarExcludeFilters = excludeFiltersList;
    }

    function setCalendarEnabled(href, enabled) {
        var list = plasmoid.configuration.enabledCalendarUrls.slice();
        var idx = list.indexOf(href);
        if (enabled && idx === -1) list.push(href);
        if (!enabled && idx !== -1) list.splice(idx, 1);
        plasmoid.configuration.enabledCalendarUrls = list;
    }

    // "".split("\n") is ["": length 1], not an empty array, so this can't
    // just be filtersText.split("\n").length - an empty filter list must
    // count as 0, not 1.
    function filterCount(filtersText) {
        return (filtersText || "").split("\n").map(function (s) { return s.trim(); })
                                   .filter(function (s) { return s.length > 0; }).length;
    }

    function setCalendarFilters(href, text) {
        var urls = plasmoid.configuration.calendarUrls;
        var idx = urls.indexOf(href);
        if (idx === -1) return;
        var filtersList = plasmoid.configuration.calendarFilters.slice();
        padTo(filtersList, urls.length, "");
        filtersList[idx] = text;
        plasmoid.configuration.calendarFilters = filtersList;
        rebuildDiscoveredFromConfig();
    }

    function setCalendarExcludeFilters(href, text) {
        var urls = plasmoid.configuration.calendarUrls;
        var idx = urls.indexOf(href);
        if (idx === -1) return;
        var excludeFiltersList = plasmoid.configuration.calendarExcludeFilters.slice();
        padTo(excludeFiltersList, urls.length, "");
        excludeFiltersList[idx] = text;
        plasmoid.configuration.calendarExcludeFilters = excludeFiltersList;
        rebuildDiscoveredFromConfig();
    }

    function setCalendarColor(href, colorValue) {
        var urls = plasmoid.configuration.calendarUrls;
        var idx = urls.indexOf(href);
        if (idx === -1) return;
        var colors = plasmoid.configuration.calendarColors.slice();
        colors[idx] = colorValue.toString();
        plasmoid.configuration.calendarColors = colors;
        rebuildDiscoveredFromConfig();
    }

    function removeCalendar(href) {
        var urls = plasmoid.configuration.calendarUrls.slice();
        var idx = urls.indexOf(href);
        if (idx === -1) return;
        var names = plasmoid.configuration.calendarNames.slice();
        var colors = plasmoid.configuration.calendarColors.slice();
        var kinds = plasmoid.configuration.calendarKinds.slice();
        var sources = plasmoid.configuration.calendarSources.slice();
        var filtersList = plasmoid.configuration.calendarFilters.slice();
        var excludeFiltersList = plasmoid.configuration.calendarExcludeFilters.slice();
        urls.splice(idx, 1);
        names.splice(idx, 1);
        colors.splice(idx, 1);
        kinds.splice(idx, 1);
        if (idx < sources.length) sources.splice(idx, 1);
        if (idx < filtersList.length) filtersList.splice(idx, 1);
        if (idx < excludeFiltersList.length) excludeFiltersList.splice(idx, 1);
        plasmoid.configuration.calendarUrls = urls;
        plasmoid.configuration.calendarNames = names;
        plasmoid.configuration.calendarColors = colors;
        plasmoid.configuration.calendarKinds = kinds;
        plasmoid.configuration.calendarSources = sources;
        plasmoid.configuration.calendarFilters = filtersList;
        plasmoid.configuration.calendarExcludeFilters = excludeFiltersList;
        setCalendarEnabled(href, false);
        if (icsEditingHref === href) cancelIcsEdit();
        rebuildDiscoveredFromConfig();
    }

    // Populates the "Add calendar by URL" form from an existing ics
    // calendar so saveIcsCalendar() below updates it in place instead of
    // adding a second one.
    function startEditIcsCalendar(cal) {
        icsEditingHref = cal.href;
        icsAddError = "";
        icsUrlField.text = cal.href;
        icsNameField.text = cal.displayName;
        icsColor = cal.color || "#3daee9";
    }

    function cancelIcsEdit() {
        icsEditingHref = "";
        icsAddError = "";
        icsUrlField.text = "";
        icsNameField.text = "";
        icsColor = "#3daee9";
    }

    // Handles both "Add" (icsEditingHref empty) and "Save" (editing an
    // existing ics calendar, populated by startEditIcsCalendar above).
    function saveIcsCalendar() {
        icsAddError = "";
        var url = CalDAV.normalizeIcsUrl(icsUrlField.text);
        if (!/^https?:\/\//i.test(url)) {
            icsAddError = i18n("Enter a webcal://, http://, or https:// address.");
            return;
        }

        var urls = plasmoid.configuration.calendarUrls.slice();
        var editingIdx = icsEditingHref !== "" ? urls.indexOf(icsEditingHref) : -1;
        var collidingIdx = urls.indexOf(url);
        if (collidingIdx !== -1 && collidingIdx !== editingIdx) {
            icsAddError = i18n("This calendar is already added.");
            return;
        }

        var names = plasmoid.configuration.calendarNames.slice();
        var colors = plasmoid.configuration.calendarColors.slice();
        var kinds = plasmoid.configuration.calendarKinds.slice();
        var sources = plasmoid.configuration.calendarSources.slice();
        var filtersList = plasmoid.configuration.calendarFilters.slice();
        var excludeFiltersList = plasmoid.configuration.calendarExcludeFilters.slice();
        padTo(sources, urls.length, "caldav");
        padTo(filtersList, urls.length, "");
        padTo(excludeFiltersList, urls.length, "");

        var name = icsNameField.text.trim() || url;
        var wasEnabled = editingIdx !== -1 && page.isEnabled(icsEditingHref);

        if (editingIdx !== -1) {
            urls[editingIdx] = url;
            names[editingIdx] = name;
            colors[editingIdx] = page.icsColor.toString();
            // kinds/sources/filters at this index are left as they were -
            // still VEVENT/"ics", and any filters already set still apply
            // to whatever the (possibly changed) URL now returns.
        } else {
            urls.push(url);
            names.push(name);
            colors.push(page.icsColor.toString());
            // Always VEVENT-only: a plain .ics feed is display-only
            // (there's nowhere to PUT a completion toggle back to), so
            // there's no VTODO handling to offer for it.
            kinds.push("VEVENT");
            sources.push("ics");
            filtersList.push("");
            excludeFiltersList.push("");
        }

        plasmoid.configuration.calendarUrls = urls;
        plasmoid.configuration.calendarNames = names;
        plasmoid.configuration.calendarColors = colors;
        plasmoid.configuration.calendarKinds = kinds;
        plasmoid.configuration.calendarSources = sources;
        plasmoid.configuration.calendarFilters = filtersList;
        plasmoid.configuration.calendarExcludeFilters = excludeFiltersList;

        if (editingIdx === -1) {
            setCalendarEnabled(url, true);
        } else if (icsEditingHref !== url) {
            // enabledCalendarUrls stores hrefs directly, so a changed URL
            // needs re-adding under its new value - and shouldn't force a
            // calendar the user had deliberately disabled back on.
            setCalendarEnabled(icsEditingHref, false);
            if (wasEnabled) setCalendarEnabled(url, true);
        }

        rebuildDiscoveredFromConfig();
        cancelIcsEdit();
    }

    // Single source of truth for the "Calendars:" list shown above -
    // called after every mutation (discovery, add-by-URL, remove, color/
    // filter edits) so `discovered` always reflects current config instead
    // of each call site building its own slightly-different shape.
    function rebuildDiscoveredFromConfig() {
        var urls = plasmoid.configuration.calendarUrls;
        var names = plasmoid.configuration.calendarNames;
        var colors = plasmoid.configuration.calendarColors;
        var kinds = plasmoid.configuration.calendarKinds;
        var sources = plasmoid.configuration.calendarSources;
        var filtersList = plasmoid.configuration.calendarFilters;
        var excludeFiltersList = plasmoid.configuration.calendarExcludeFilters;
        var out = [];
        for (var i = 0; i < urls.length; i++) {
            out.push({
                href: urls[i],
                displayName: names[i],
                color: colors[i],
                kinds: (kinds[i] || "VEVENT").split("+"),
                source: sources[i] || "caldav",
                filtersText: filtersList[i] || "",
                excludeFiltersText: excludeFiltersList[i] || ""
            });
        }
        discovered = out;
    }

    Component.onCompleted: {
        // Pre-populate the list from calendars already known from a previous
        // discovery, so re-opening settings still shows current selections.
        rebuildDiscoveredFromConfig();
        showManualFields = usernameField.text.length > 0;
    }
}
