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
    // [{ href, name, color, kinds }], refreshed alongside agendaItems - fed
    // to FullRepresentation's add-item calendar pickers.
    property var availableCalendars: []
    // Error from the last create/edit/delete attempt, and a counter
    // FullRepresentation watches to know when to close the item form popup
    // on success - root has no direct way to call a function on
    // FullRepresentation (or the popup it owns), only properties it can
    // react to.
    property string formError: ""
    property int itemActionToken: 0
    // Ticks once a minute so "is this event in the past" (see EventDelegate)
    // stays live between refreshes, rather than being frozen at whatever it
    // was the last time refresh() happened to run (up to refreshInterval
    // minutes - as long as 4 hours - stale otherwise).
    property date currentTime: new Date()

    // Separate data/loading state for the month-calendar view (Appearance
    // setting "viewMode"). Kept independent of agendaItems above: browsing
    // to a different month needs events from outside the daysAhead window
    // refresh() fetches, so it's populated by its own refreshMonth() calls.
    property var monthEvents: []
    property bool monthLoading: false
    property string monthError: ""
    property date monthCursor: DateUtils.startOfMonth(new Date())
    property int monthRequestToken: 0

    property bool accountConfigured: plasmoid.configuration.serverUrl.length > 0 &&
                                      plasmoid.configuration.username.length > 0 &&
                                      plasmoid.configuration.appPassword.length > 0

    // metadata.json's Icon field only supports a system icon-theme name -
    // Plasma's widget-explorer list resolves it via QIcon::fromTheme, not
    // a bundled file, so the "Add Widgets" card can't show this logo that
    // way. The running widget's own icon (panel/system tray/compact
    // representation) is set here instead via plasmoid.file(), which
    // resolves a path relative to contents/ within this package - the
    // documented mechanism for a plasmoid's own bundled icon. Falls back
    // to a system icon if the bundled file can't be found for some reason
    // (plasmoid.file returns "" in that case, which Plasmoid.icon would
    // otherwise render as no icon at all).
    Plasmoid.icon: plasmoid.file("", "icon.svg") || "view-calendar"
    Plasmoid.title: i18n("Nextcloud Caldav")
    toolTipMainText: nextEvent ? nextEvent.summary : i18n("Nextcloud Caldav")
    toolTipSubText: lastError !== "" ? errorSummary(lastError) : toolTipSummary()

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
        availableCalendars: root.availableCalendars
        formError: root.formError
        itemActionToken: root.itemActionToken
        currentTime: root.currentTime
        monthEvents: root.monthEvents
        monthLoading: root.monthLoading
        monthCursor: root.monthCursor
        onRefreshRequested: root.refresh()
        onToggleTask: root.toggleTaskCompletion(task)
        onOpenConfigureRequested: plasmoid.internalAction("configure").trigger()
        onCreateTaskRequested: root.createTask(calendarHref, summary, due, description, location)
        onCreateEventRequested: root.createEvent(calendarHref, summary, start, end, allDay, description, location)
        onEditTaskRequested: root.updateTask(task, summary, due, description, location)
        onEditEventRequested: root.updateEvent(event, summary, start, end, allDay, description, location)
        onDeleteTaskRequested: root.deleteTask(task)
        onDeleteEventRequested: root.deleteEvent(event)
        onMonthNavigate: root.changeMonth(delta)
        onMonthJump: root.jumpToMonth(month)
    }

    Timer {
        id: clockTimer
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.currentTime = new Date()
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
        function onDisplayModeChanged() { root.refresh() }
        function onViewModeChanged() {
            if (plasmoid.configuration.viewMode === 1 /* Month */ &&
                root.monthEvents.length === 0 && !root.monthLoading) {
                root.refreshMonth(root.monthCursor);
            }
        }
    }

    Component.onCompleted: {
        console.log("Nextcloud Caldav: build 0.5.9 starting");
        refresh();
        if (plasmoid.configuration.viewMode === 1 /* Month */) refreshMonth(monthCursor);
    }

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

    function wantsEvents() {
        return plasmoid.configuration.displayMode !== 2 /* TasksOnly */;
    }

    function wantsTasks() {
        var mode = plasmoid.configuration.displayMode;
        if (mode === 1 /* EventsOnly */) return false;
        if (mode === 2 /* TasksOnly */) return true;
        return plasmoid.configuration.showTasks;
    }

    function refresh() {
        if (!accountConfigured) {
            lastError = "unconfigured";
            agendaItems = [];
            return;
        }
        var calendars = enabledCalendarList();
        console.log("CalDAV Agenda: refresh() - enabled calendars:", JSON.stringify(calendars));
        availableCalendars = calendars;
        if (calendars.length === 0) {
            lastError = "nocalendars";
            agendaItems = [];
            return;
        }

        // Keep the month-calendar view in sync with every refresh (the
        // timer, the manual refresh button, and after creating/toggling an
        // item all call refresh() already) - it has its own independent
        // fetch since it covers a different date range, and previously
        // only got refreshed by navigating the month view itself, so a
        // newly created event never showed up there until you clicked away
        // and back.
        refreshMonth(monthCursor);

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
            if (wantsEvents() && cal.kinds.indexOf("VEVENT") !== -1) {
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
                                        e.calendarHref = cal.href;
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
            if (wantsTasks() && cal.kinds.indexOf("VTODO") !== -1) {
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

    // Re-orders an already-sorted list of tasks so a subtask (parentUid
    // pointing at another task's uid) immediately follows its parent,
    // recursively, and stamps a `depth` (0 = top-level) used for visual
    // indentation. A subtask whose parent isn't in this same list (e.g. it
    // fell into a different day-bucket, or the parent is filtered out) is
    // just treated as top-level here - there's no sensible bucket to move
    // it into.
    function orderTasksWithHierarchy(tasks) {
        var byUid = {};
        tasks.forEach(function (t) { if (t.uid) byUid[t.uid] = t; });
        var childrenOf = {};
        var roots = [];
        tasks.forEach(function (t) {
            var parent = t.parentUid && byUid[t.parentUid];
            if (parent && parent !== t) {
                (childrenOf[parent.uid] = childrenOf[parent.uid] || []).push(t);
            } else {
                roots.push(t);
            }
        });
        var out = [];
        function visit(t, depth) {
            t.depth = depth;
            out.push(t);
            (childrenOf[t.uid] || []).forEach(function (c) { visit(c, depth + 1); });
        }
        roots.forEach(function (t) { visit(t, 0); });
        return out;
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
        var showTasks = wantsTasks();
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
            orderTasksWithHierarchy(overdue).forEach(function (t) { out.push({ type: "task", data: t }); });
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
            orderTasksWithHierarchy(dayTasks).forEach(function (t) { out.push({ type: "task", data: t }); });
        }

        if (showTasks && noDue.length > 0) {
            noDue.sort(function (a, b) { return priorityRank(a) - priorityRank(b); });
            out.push({ type: "sectionHeader", label: "noDueDate", count: noDue.length });
            orderTasksWithHierarchy(noDue).forEach(function (t) { out.push({ type: "task", data: t }); });
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
        CalDAV.updateResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, task.href, task.etag, icsText,
            function (err) {
                if (!err) root.refresh();
            });
    }

    function updateTask(task, summary, due, description, location) {
        formError = "";
        var icsText = ICAL.patchTodoFields(task, { summary: summary, due: due || null, description: description, location: location });
        CalDAV.updateResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, task.href, task.etag, icsText,
            function (err) {
                if (err) {
                    console.warn("CalDAV Agenda: failed to update task:", err);
                    formError = errorSummary(err);
                } else {
                    root.itemActionToken++;
                    root.refresh();
                }
            });
    }

    function deleteTask(task) {
        formError = "";
        CalDAV.deleteResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, task.href, task.etag,
            function (err) {
                if (err) {
                    console.warn("CalDAV Agenda: failed to delete task:", err);
                    formError = errorSummary(err);
                } else {
                    root.itemActionToken++;
                    root.refresh();
                }
            });
    }

    // Events don't carry their own resource href/etag from the normal
    // fetch path (see fetchEventResource's comment in caldav.js), so
    // editing/deleting one resolves its real resource fresh first, then
    // acts on that.
    function updateEvent(event, summary, start, end, allDay, description, location) {
        formError = "";
        CalDAV.fetchEventResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, event.calendarHref, event.uid,
            function (err, resource) {
                if (err) { console.warn("CalDAV Agenda: failed to locate event for editing:", err); formError = errorSummary(err); return; }
                var icsText = ICAL.patchEventFields(resource.icsText, { summary: summary, start: start, end: end, allDay: allDay, description: description, location: location });
                CalDAV.updateResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
                    plasmoid.configuration.appPassword, resource.href, resource.etag, icsText,
                    function (err2) {
                        if (err2) {
                            console.warn("CalDAV Agenda: failed to update event:", err2);
                            formError = errorSummary(err2);
                        } else {
                            root.itemActionToken++;
                            root.refresh();
                        }
                    });
            });
    }

    function deleteEvent(event) {
        formError = "";
        CalDAV.fetchEventResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, event.calendarHref, event.uid,
            function (err, resource) {
                if (err) { console.warn("CalDAV Agenda: failed to locate event for deletion:", err); formError = errorSummary(err); return; }
                CalDAV.deleteResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
                    plasmoid.configuration.appPassword, resource.href, resource.etag,
                    function (err2) {
                        if (err2) {
                            console.warn("CalDAV Agenda: failed to delete event:", err2);
                            formError = errorSummary(err2);
                        } else {
                            root.itemActionToken++;
                            root.refresh();
                        }
                    });
            });
    }

    function createTask(calendarHref, summary, due, description, location) {
        formError = "";
        var uid = ICAL.generateUid();
        var icsText = ICAL.buildVTodoIcs({ uid: uid, summary: summary, due: due || null, description: description, location: location, parentUid: null });
        CalDAV.createResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, calendarHref, uid, icsText,
            function (err) {
                if (err) {
                    console.warn("CalDAV Agenda: failed to create task:", err);
                    formError = errorSummary(err);
                } else {
                    root.itemActionToken++;
                    root.refresh();
                }
            });
    }

    function createEvent(calendarHref, summary, start, end, allDay, description, location) {
        formError = "";
        var uid = ICAL.generateUid();
        var icsText = ICAL.buildVEventIcs({ uid: uid, summary: summary, start: start, end: end, allDay: allDay, description: description, location: location });
        CalDAV.createResource(plasmoid.configuration.serverUrl, plasmoid.configuration.username,
            plasmoid.configuration.appPassword, calendarHref, uid, icsText,
            function (err) {
                if (err) {
                    console.warn("CalDAV Agenda: failed to create event:", err);
                    formError = errorSummary(err);
                } else {
                    root.itemActionToken++;
                    root.refresh();
                }
            });
    }

    function toolTipSummary() {
        var mode = plasmoid.configuration.displayMode;
        if (mode === 1 /* EventsOnly */) return i18np("%1 event today", "%1 events today", todayCount);
        if (mode === 2 /* TasksOnly */) return i18np("%1 task overdue", "%1 tasks overdue", overdueCount);
        return i18n("%1 events today, %2 tasks overdue", todayCount, overdueCount);
    }

    function changeMonth(delta) {
        monthCursor = delta === 0 ? monthCursor : DateUtils.addMonths(monthCursor, delta);
        refreshMonth(monthCursor);
    }

    function jumpToMonth(monthDate) {
        monthCursor = DateUtils.startOfMonth(monthDate);
        refreshMonth(monthCursor);
    }

    // Populates monthEvents for the given month. Independent of refresh()'s
    // daysAhead-bounded event fetch above - browsing to a different month
    // needs a CalDAV request scoped to that month specifically, since
    // refresh() never requests data outside its own upcoming-days window.
    function refreshMonth(monthDate) {
        if (!accountConfigured) return;
        var calendars = enabledCalendarList().filter(function (c) { return c.kinds.indexOf("VEVENT") !== -1; });
        var token = ++monthRequestToken;
        if (calendars.length === 0) {
            monthEvents = [];
            monthLoading = false;
            return;
        }

        monthLoading = true;
        monthError = "";

        var serverUrl = plasmoid.configuration.serverUrl;
        var username = plasmoid.configuration.username;
        var password = plasmoid.configuration.appPassword;

        var rangeStart = DateUtils.startOfMonth(monthDate);
        var rangeEnd = DateUtils.addMonths(rangeStart, 1);

        var pending = calendars.length;
        var collected = [];
        var firstError = null;

        function checkDone() {
            pending--;
            // A newer changeMonth()/refreshMonth() call superseded this one
            // (e.g. rapid Next-month clicks) - drop this response rather
            // than clobbering monthEvents with stale data.
            if (pending <= 0 && token === monthRequestToken) {
                monthLoading = false;
                monthError = firstError || "";
                monthEvents = collected;
            }
        }

        calendars.forEach(function (cal) {
            try {
                CalDAV.fetchEvents(serverUrl, username, password, cal.href, rangeStart, rangeEnd, function (err, items) {
                    try {
                        if (err) {
                            firstError = firstError || err;
                            return;
                        }
                        items.forEach(function (it) {
                            try {
                                var parsed = ICAL.parseCalendarObject(it.icsText, it.href, it.etag, rangeStart, rangeEnd);
                                parsed.events.forEach(function (e) {
                                    e.calendarColor = cal.color;
                                    e.calendarName = cal.name;
                                    e.calendarHref = cal.href;
                                    collected.push(e);
                                });
                            } catch (parseErr) {
                                console.warn("CalDAV Agenda: skipping malformed event (month view) in", cal.name, ":", parseErr);
                            }
                        });
                    } finally {
                        checkDone();
                    }
                });
            } catch (initErr) {
                console.warn("CalDAV Agenda: failed to start month events request for", cal.name, ":", initErr);
                firstError = firstError || "network";
                checkDone();
            }
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
