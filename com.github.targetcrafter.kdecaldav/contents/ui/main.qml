import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

import "../code/caldav.js" as CalDAV
import "../code/ical.js" as ICAL
import "../code/dateutils.js" as DateUtils

PlasmoidItem {
    id: root

    // Flat, pre-grouped render list consumed by FullRepresentation:
    // { type: "sectionHeader", label, count } |
    // { type: "dayHeader", date } |
    // { type: "event", data } | { type: "task", data }
    property var agendaItems: []
    property var nextEvent: null
    property int todayCount: 0
    property int overdueCount: 0
    property bool isLoading: false
    property string lastError: ""
    property date lastUpdated

    property bool accountConfigured: plasmoid.configuration.serverUrl.length > 0 &&
                                      plasmoid.configuration.username.length > 0 &&
                                      plasmoid.configuration.appPassword.length > 0

    Plasmoid.icon: "view-calendar"
    Plasmoid.title: i18n("CalDAV Agenda")
    toolTipMainText: nextEvent ? nextEvent.summary : i18n("CalDAV Agenda")
    toolTipSubText: lastError !== "" ? errorSummary(lastError) : i18n("%1 events today, %2 tasks overdue", todayCount, overdueCount)

    Plasmoid.status: (overdueCount > 0) ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    compactRepresentation: CompactRepresentation {
        nextEvent: root.nextEvent
        todayCount: root.todayCount
        overdueCount: root.overdueCount
        isLoading: root.isLoading
        lastError: root.lastError
    }

    fullRepresentation: FullRepresentation {
        agendaItems: root.agendaItems
        isLoading: root.isLoading
        lastError: root.lastError
        lastUpdated: root.lastUpdated
        accountConfigured: root.accountConfigured
        onRefreshRequested: root.refresh()
        onToggleTask: root.toggleTaskCompletion(task)
        onOpenConfigureRequested: plasmoid.internalAction("configure").trigger()
    }

    Timer {
        id: refreshTimer
        interval: Math.max(1, plasmoid.configuration.refreshInterval) * 60 * 1000
        running: root.accountConfigured
        repeat: true
        onTriggered: root.refresh()
    }

    // Belt-and-braces: if a refresh hasn't finished within 30s (a request
    // that never reaches XMLHttpRequest.DONE, rather than one that errors
    // out normally), stop the spinner and surface it as a network problem
    // instead of leaving the popup stuck loading forever.
    Timer {
        id: loadWatchdog
        interval: 30000
        repeat: false
        onTriggered: {
            if (root.isLoading) {
                console.warn("CalDAV Agenda: refresh timed out after", interval / 1000, "s");
                root.isLoading = false;
                root.lastError = "timeout";
            }
        }
    }

    Connections {
        target: plasmoid.configuration
        function onServerUrlChanged() { root.refresh() }
        function onUsernameChanged() { root.refresh() }
        function onAppPasswordChanged() { root.refresh() }
        function onEnabledCalendarUrlsChanged() { root.refresh() }
        function onDaysAheadChanged() { root.refresh() }
        function onShowTasksChanged() { root.refresh() }
        function onShowCompletedTasksChanged() { root.refresh() }
    }

    Component.onCompleted: refresh()

    function enabledCalendarList() {
        var urls = plasmoid.configuration.calendarUrls;
        var names = plasmoid.configuration.calendarNames;
        var colors = plasmoid.configuration.calendarColors;
        var kinds = plasmoid.configuration.calendarKinds;
        var enabled = plasmoid.configuration.enabledCalendarUrls;
        var out = [];
        for (var i = 0; i < urls.length; i++) {
            if (enabled.indexOf(urls[i]) === -1) continue;
            out.push({
                href: urls[i],
                name: names[i] || urls[i],
                color: colors[i] || "#3daee9",
                kinds: (kinds[i] || "VEVENT").split("+")
            });
        }
        return out;
    }

    function refresh() {
        if (!accountConfigured) {
            lastError = "unconfigured";
            agendaItems = [];
            return;
        }
        var calendars = enabledCalendarList();
        console.log("CalDAV Agenda: refresh() - enabled calendars:", JSON.stringify(calendars));
        if (calendars.length === 0) {
            lastError = "nocalendars";
            agendaItems = [];
            return;
        }

        isLoading = true;
        lastError = "";
        loadWatchdog.restart();

        var serverUrl = plasmoid.configuration.serverUrl;
        var username = plasmoid.configuration.username;
        var password = plasmoid.configuration.appPassword;

        var now = new Date();
        var rangeStart = DateUtils.startOfDay(now);
        var rangeEnd = DateUtils.addDays(rangeStart, plasmoid.configuration.daysAhead);

        var pending = 0;
        var collectedEvents = [];
        var collectedTodos = [];
        var firstError = null;

        function checkDone() {
            pending--;
            if (pending <= 0) {
                loadWatchdog.stop();
                finishRefresh(collectedEvents, collectedTodos, firstError);
            }
        }

        // Every fetch callback runs its body inside try/finally so that
        // whatever goes wrong - a malformed server response, a bug in the
        // parser, anything - checkDone() still fires. Without this a single
        // unexpected exception thrown inside an XHR callback is swallowed by
        // the QML engine and leaves the refresh (and its spinner) hung
        // forever, since pending would never reach zero.
        calendars.forEach(function (cal, index) {
            console.log("CalDAV Agenda: processing calendar", index + 1, "of", calendars.length, "-", cal.name);
            if (cal.kinds.indexOf("VEVENT") !== -1) {
                pending++;
                // The request-initiation call itself is also wrapped in
                // try/catch, not just its response callback: if it throws
                // synchronously (before the async XHR is even registered),
                // an uncaught exception here would both abort this whole
                // forEach loop (skipping every calendar after this one) and
                // leave checkDone() never called for this entry, hanging
                // the refresh permanently. Both symptoms were observed
                // before this was added.
                try {
                    console.log("CalDAV Agenda: requesting events for", cal.name, "at", CalDAV.resolveHref(serverUrl, cal.href));
                    CalDAV.fetchEvents(serverUrl, username, password, cal.href, rangeStart, rangeEnd, function (err, items) {
                        console.log("CalDAV Agenda: events response for", cal.name, "- error:", err, "count:", items ? items.length : 0);
                        try {
                            if (err) {
                                console.warn("CalDAV Agenda: fetching events for", cal.name, "failed:", err);
                                firstError = firstError || err;
                                return;
                            }
                            items.forEach(function (it) {
                                try {
                                    var parsed = ICAL.parseCalendarObject(it.icsText, it.href, it.etag, rangeStart, rangeEnd);
                                    parsed.events.forEach(function (e) {
                                        e.calendarColor = cal.color;
                                        e.calendarName = cal.name;
                                        collectedEvents.push(e);
                                    });
                                } catch (parseErr) {
                                    console.warn("CalDAV Agenda: skipping malformed event in", cal.name, ":", parseErr);
                                }
                            });
                        } catch (fatalErr) {
                            console.warn("CalDAV Agenda: unexpected error handling events for", cal.name, ":", fatalErr);
                            firstError = firstError || "parse";
                        } finally {
                            checkDone();
                        }
                    });
                } catch (initErr) {
                    console.warn("CalDAV Agenda: failed to start events request for", cal.name, ":", initErr);
                    firstError = firstError || "network";
                    checkDone();
                }
            }
            if (plasmoid.configuration.showTasks && cal.kinds.indexOf("VTODO") !== -1) {
                pending++;
                try {
                    console.log("CalDAV Agenda: requesting tasks for", cal.name, "at", CalDAV.resolveHref(serverUrl, cal.href));
                    CalDAV.fetchTodos(serverUrl, username, password, cal.href, function (err, items) {
                        console.log("CalDAV Agenda: tasks response for", cal.name, "- error:", err, "count:", items ? items.length : 0);
                        try {
                            if (err) {
                                console.warn("CalDAV Agenda: fetching tasks for", cal.name, "failed:", err);
                                firstError = firstError || err;
                                return;
                            }
                            items.forEach(function (it) {
                                try {
                                    var parsed = ICAL.parseCalendarObject(it.icsText, it.href, it.etag, rangeStart, rangeEnd);
                                    parsed.todos.forEach(function (t) {
                                        t.calendarColor = cal.color;
                                        t.calendarName = cal.name;
                                        t.calendarHref = cal.href;
                                        collectedTodos.push(t);
                                    });
                                } catch (parseErr) {
                                    console.warn("CalDAV Agenda: skipping malformed task in", cal.name, ":", parseErr);
                                }
                            });
                        } catch (fatalErr) {
                            console.warn("CalDAV Agenda: unexpected error handling tasks for", cal.name, ":", fatalErr);
                            firstError = firstError || "parse";
                        } finally {
                            checkDone();
                        }
                    });
                } catch (initErr) {
                    console.warn("CalDAV Agenda: failed to start tasks request for", cal.name, ":", initErr);
                    firstError = firstError || "network";
                    checkDone();
                }
            }
        });
    }

    function priorityRank(task) {
        // RFC 5545: 1 = highest, 9 = lowest, 0 = undefined. Rank undefined last.
        return task.priority > 0 ? task.priority : 10;
    }

    function sortEvents(a, b) {
        if (a.allDay !== b.allDay) return a.allDay ? -1 : 1;
        return a.dtstart.getTime() - b.dtstart.getTime();
    }

    function finishRefresh(events, todos, err) {
        isLoading = false;
        lastUpdated = new Date();
        lastError = err || "";

        var now = new Date();
        var showCompleted = plasmoid.configuration.showCompletedTasks;
        var showTasks = plasmoid.configuration.showTasks;
        todos = showTasks ? todos.filter(function (t) { return showCompleted || t.status !== "COMPLETED"; }) : [];

        var overdue = todos.filter(function (t) { return t.due && t.status !== "COMPLETED" && DateUtils.isOverdue(t.due, now); });
        var noDue = todos.filter(function (t) { return !t.due; });
        var dueByDay = {};
        todos.forEach(function (t) {
            if (!t.due) return;
            if (t.status !== "COMPLETED" && DateUtils.isOverdue(t.due, now)) return;
            var key = DateUtils.dayKey(t.due);
            (dueByDay[key] = dueByDay[key] || []).push(t);
        });

        var eventsByDay = {};
        events.forEach(function (e) {
            if (!e.dtstart) return;
            var key = DateUtils.dayKey(e.dtstart);
            (eventsByDay[key] = eventsByDay[key] || []).push(e);
        });

        var out = [];
        if (overdue.length > 0) {
            overdue.sort(function (a, b) { return a.due.getTime() - b.due.getTime(); });
            out.push({ type: "sectionHeader", label: "overdue", count: overdue.length });
            overdue.forEach(function (t) { out.push({ type: "task", data: t }); });
        }

        var start = DateUtils.startOfDay(now);
        var daysAhead = plasmoid.configuration.daysAhead;
        for (var i = 0; i < daysAhead; i++) {
            var d = DateUtils.addDays(start, i);
            var key = DateUtils.dayKey(d);
            var dayEvents = (eventsByDay[key] || []).slice().sort(sortEvents);
            var dayTasks = (dueByDay[key] || []).slice().sort(function (a, b) { return priorityRank(a) - priorityRank(b); });
            if (dayEvents.length === 0 && dayTasks.length === 0) continue;
            out.push({ type: "dayHeader", date: d });
            dayEvents.forEach(function (e) { out.push({ type: "event", data: e }); });
            dayTasks.forEach(function (t) { out.push({ type: "task", data: t }); });
        }

        if (showTasks && noDue.length > 0) {
            out.push({ type: "sectionHeader", label: "noDueDate", count: noDue.length });
            noDue.forEach(function (t) { out.push({ type: "task", data: t }); });
        }

        agendaItems = out;
        overdueCount = overdue.length;
        todayCount = (eventsByDay[DateUtils.dayKey(now)] || []).length;
        nextEvent = computeNextEvent(events, now);
    }

    function computeNextEvent(events, now) {
        var upcoming = events.filter(function (e) {
            return e.dtstart && (e.dtstart.getTime() >= now.getTime() ||
                   (e.dtend && e.dtend.getTime() > now.getTime()));
        });
        if (upcoming.length === 0) return null;
        upcoming.sort(sortEvents);
        return upcoming[0];
    }

    function toggleTaskCompletion(task) {
        var completed = task.status !== "COMPLETED";
        var icsText = ICAL.patchTodoStatus(task, completed);
        CalDAV.putTodo(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, task.href, task.etag, icsText,
            function (err) {
                if (!err) root.refresh();
            });
    }

    function errorSummary(code) {
        switch (code) {
        case "unconfigured": return i18n("Not set up yet");
        case "nocalendars": return i18n("No calendars selected");
        case "auth": return i18n("Sign-in failed");
        case "network": return i18n("Can't reach server");
        case "notfound": return i18n("Server address not found");
        case "parse": return i18n("Couldn't read calendar data");
        case "timeout": return i18n("Timed out waiting for the server");
        default: return i18n("Something went wrong");
        }
    }
}
