.pragma library

// Minimal, dependency-free iCalendar (RFC 5545) reader tailored to what a
// CalDAV calendar-query returns: one or more VCALENDAR blobs, each holding a
// single VEVENT or VTODO (plus possible RECURRENCE-ID overrides for a
// recurring master). Not a full RFC 5545 implementation.
//
// Timezones: DATE-TIME values with a trailing "Z" are parsed as UTC.
// Values carrying a TZID parameter are treated as wall-clock time in the
// *system* timezone (there is no bundled IANA tzdata to resolve arbitrary
// TZIDs against). For most single-timezone home setups this matches the
// Nextcloud server's timezone; it will be off for shared calendars whose
// events were created in a different timezone than the desktop's.

function unfold(text) {
    // RFC 5545 line folding: a CRLF followed by a space/tab continues the
    // previous line. Normalize CRLF/CR to LF first, then unfold.
    var normalized = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    return normalized.replace(/\n[ \t]/g, "");
}

function parseLine(line) {
    var colonIdx = -1;
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
        var ch = line[i];
        if (ch === '"') inQuotes = !inQuotes;
        if (ch === ':' && !inQuotes) { colonIdx = i; break; }
    }
    if (colonIdx === -1) return null;
    var head = line.substring(0, colonIdx);
    var value = line.substring(colonIdx + 1);
    var parts = head.split(';');
    var name = parts[0].toUpperCase();
    var params = {};
    for (var p = 1; p < parts.length; p++) {
        var eq = parts[p].indexOf('=');
        if (eq === -1) continue;
        var pname = parts[p].substring(0, eq).toUpperCase();
        var pval = parts[p].substring(eq + 1).replace(/^"|"$/g, '');
        params[pname] = pval;
    }
    return { name: name, params: params, value: value };
}

function unescapeText(value) {
    return value
        .replace(/\\n/gi, "\n")
        .replace(/\\,/g, ",")
        .replace(/\\;/g, ";")
        .replace(/\\\\/g, "\\");
}

// Inverse of unescapeText, for embedding user-entered text in a new ICS
// property value. Order matters: backslashes first, so escaping the other
// characters doesn't get re-escaped.
function escapeText(value) {
    return String(value)
        .replace(/\\/g, "\\\\")
        .replace(/\n/g, "\\n")
        .replace(/,/g, "\\,")
        .replace(/;/g, "\\;");
}

function generateUid() {
    var chars = "0123456789abcdef";
    var s = "";
    for (var i = 0; i < 32; i++) s += chars[Math.floor(Math.random() * 16)];
    return s.substring(0, 8) + "-" + s.substring(8, 12) + "-" + s.substring(12, 16) +
           "-" + s.substring(16, 20) + "-" + s.substring(20, 32) + "@kdecaldav";
}

function pad(n) { return (n < 10 ? "0" : "") + n; }

// Parses a DATE or DATE-TIME property value into { date: Date, allDay: bool }.
function parseDateTime(prop) {
    var v = prop.value;
    if (prop.params.VALUE === "DATE" || /^\d{8}$/.test(v)) {
        var y = parseInt(v.substring(0, 4), 10);
        var mo = parseInt(v.substring(4, 6), 10) - 1;
        var d = parseInt(v.substring(6, 8), 10);
        return { date: new Date(y, mo, d), allDay: true };
    }
    var m = v.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$/);
    if (!m) return { date: new Date(v), allDay: false };
    var year = parseInt(m[1], 10), mon = parseInt(m[2], 10) - 1, day = parseInt(m[3], 10);
    var hh = parseInt(m[4], 10), mm = parseInt(m[5], 10), ss = parseInt(m[6], 10);
    var isUtc = !!m[7];
    var date = isUtc ? new Date(Date.UTC(year, mon, day, hh, mm, ss))
                      : new Date(year, mon, day, hh, mm, ss);
    return { date: date, allDay: false };
}

function formatDateTimeUTC(date) {
    return date.getUTCFullYear() + pad(date.getUTCMonth() + 1) + pad(date.getUTCDate()) + "T" +
           pad(date.getUTCHours()) + pad(date.getUTCMinutes()) + pad(date.getUTCSeconds()) + "Z";
}

// Splits a VCALENDAR blob's unfolded lines into top-level component blocks.
function splitComponents(lines, componentName) {
    var blocks = [];
    var current = null;
    var beginTag = "BEGIN:" + componentName;
    var endTag = "END:" + componentName;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === beginTag) {
            current = [];
        } else if (line === endTag) {
            if (current) blocks.push(current);
            current = null;
        } else if (current) {
            current.push(line);
        }
    }
    return blocks;
}

function propsToMap(lines) {
    var map = {};
    for (var i = 0; i < lines.length; i++) {
        var prop = parseLine(lines[i]);
        if (!prop) continue;
        if (!map[prop.name]) map[prop.name] = [];
        map[prop.name].push(prop);
    }
    return map;
}

function first(map, name) {
    return map[name] ? map[name][0] : null;
}

function textValue(map, name) {
    var p = first(map, name);
    return p ? unescapeText(p.value) : "";
}

function buildEvent(map, href, etag) {
    var dtstartProp = first(map, "DTSTART");
    var dtendProp = first(map, "DTEND");
    var durationProp = first(map, "DURATION");
    var start = dtstartProp ? parseDateTime(dtstartProp) : null;
    var end = null;
    if (dtendProp) {
        end = parseDateTime(dtendProp);
    } else if (start && durationProp) {
        end = { date: applyDuration(start.date, durationProp.value), allDay: start.allDay };
    } else if (start) {
        end = { date: start.date, allDay: start.allDay };
    }
    var recurrenceIdProp = first(map, "RECURRENCE-ID");
    return {
        kind: "VEVENT",
        uid: textValue(map, "UID"),
        summary: textValue(map, "SUMMARY"),
        location: textValue(map, "LOCATION"),
        description: textValue(map, "DESCRIPTION"),
        status: textValue(map, "STATUS"),
        dtstart: start ? start.date : null,
        dtend: end ? end.date : null,
        allDay: start ? start.allDay : false,
        rrule: first(map, "RRULE") ? first(map, "RRULE").value : null,
        exdates: (map["EXDATE"] || []).map(function (p) { return parseDateTime(p).date; }),
        recurrenceId: recurrenceIdProp ? parseDateTime(recurrenceIdProp).date : null,
        isRecurring: !!first(map, "RRULE") || !!recurrenceIdProp,
        href: href,
        etag: etag
    };
}

function buildTodo(map, href, etag) {
    var dueProp = first(map, "DUE");
    var dtstartProp = first(map, "DTSTART");
    var completedProp = first(map, "COMPLETED");
    var due = dueProp ? parseDateTime(dueProp) : null;
    var dtstart = dtstartProp ? parseDateTime(dtstartProp) : null;
    var completed = completedProp ? parseDateTime(completedProp).date : null;
    var percentProp = first(map, "PERCENT-COMPLETE");
    var priorityProp = first(map, "PRIORITY");
    // A bare RELATED-TO (or explicit RELTYPE=PARENT) names this task's
    // parent's UID - that's how Nextcloud Tasks (and this app's own
    // subtask creation) represents subtasks. RELTYPE=CHILD/SIBLING point
    // the other direction and aren't a "this task's parent" relationship,
    // so they're deliberately not treated as one here.
    var relatedTo = null;
    var relatedProps = map["RELATED-TO"] || [];
    for (var r = 0; r < relatedProps.length; r++) {
        var reltype = relatedProps[r].params.RELTYPE;
        if (!reltype || reltype.toUpperCase() === "PARENT") {
            relatedTo = relatedProps[r].value;
            break;
        }
    }
    return {
        kind: "VTODO",
        uid: textValue(map, "UID"),
        summary: textValue(map, "SUMMARY"),
        description: textValue(map, "DESCRIPTION"),
        status: textValue(map, "STATUS") || "NEEDS-ACTION",
        due: due ? due.date : null,
        dueAllDay: due ? due.allDay : false,
        dtstart: dtstart ? dtstart.date : null,
        completed: completed,
        percentComplete: percentProp ? parseInt(percentProp.value, 10) : 0,
        priority: priorityProp ? parseInt(priorityProp.value, 10) : 0,
        parentUid: relatedTo,
        href: href,
        etag: etag,
        rawLines: null // filled in by caller for PUT round-trips
    };
}

function applyDuration(date, durationStr) {
    var m = durationStr.match(/^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/);
    if (!m) return date;
    var sign = m[1] === "-" ? -1 : 1;
    var weeks = parseInt(m[2] || "0", 10), days = parseInt(m[3] || "0", 10);
    var hours = parseInt(m[4] || "0", 10), mins = parseInt(m[5] || "0", 10), secs = parseInt(m[6] || "0", 10);
    var totalMs = sign * (((weeks * 7 + days) * 24 * 60 * 60) + hours * 3600 + mins * 60 + secs) * 1000;
    return new Date(date.getTime() + totalMs);
}

// Parses one CalDAV multi-status "calendar-data" payload (a full VCALENDAR
// text, possibly containing several VEVENT/VTODO blocks for a recurring
// series and its overrides) into event/todo instances, expanding any
// un-expanded RRULE within [rangeStart, rangeEnd).
function parseCalendarObject(icsText, href, etag, rangeStart, rangeEnd) {
    var lines = unfold(icsText).split("\n").map(function (l) { return l.replace(/\s+$/, ""); }).filter(function (l) { return l.length > 0; });

    var events = [];
    var todos = [];

    var veventBlocks = splitComponents(lines, "VEVENT");
    var vtodoBlocks = splitComponents(lines, "VTODO");

    var masters = [];
    var overrides = [];
    for (var i = 0; i < veventBlocks.length; i++) {
        var map = propsToMap(veventBlocks[i]);
        var ev = buildEvent(map, href, etag);
        if (ev.recurrenceId) overrides.push(ev); else masters.push(ev);
    }

    for (var j = 0; j < masters.length; j++) {
        var master = masters[j];
        if (master.rrule) {
            var overridesByTime = {};
            for (var k = 0; k < overrides.length; k++) {
                if (overrides[k].uid === master.uid) {
                    overridesByTime[overrides[k].recurrenceId.getTime()] = overrides[k];
                }
            }
            var instances = expandRRule(master, master.rrule, master.exdates, overridesByTime, rangeStart, rangeEnd);
            for (var n = 0; n < instances.length; n++) events.push(instances[n]);
        } else if (!master.dtstart || (master.dtstart < rangeEnd && (master.dtend ? master.dtend > rangeStart : master.dtstart >= rangeStart))) {
            events.push(master);
        }
    }
    // Non-recurring overrides delivered without their master in this payload
    // (shouldn't normally happen from a single calendar-data blob, but be safe).
    for (var o = 0; o < overrides.length; o++) {
        var already = events.some(function (e) { return e.uid === overrides[o].uid && e.dtstart && overrides[o].dtstart && e.dtstart.getTime() === overrides[o].dtstart.getTime(); });
        if (!already) events.push(overrides[o]);
    }

    for (var t = 0; t < vtodoBlocks.length; t++) {
        var tmap = propsToMap(vtodoBlocks[t]);
        var todo = buildTodo(tmap, href, etag);
        todo.rawLines = vtodoBlocks[t];
        todos.push(todo);
    }

    return { events: events, todos: todos };
}

var FREQ_MS = { DAILY: 24 * 60 * 60 * 1000, WEEKLY: 7 * 24 * 60 * 60 * 1000 };
var WEEKDAY_CODES = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

function parseRRule(rrule) {
    var out = { freq: null, interval: 1, count: null, until: null, byday: null };
    var parts = rrule.split(';');
    for (var i = 0; i < parts.length; i++) {
        var kv = parts[i].split('=');
        var key = kv[0].toUpperCase();
        var val = kv[1];
        if (!val) continue;
        if (key === "FREQ") out.freq = val.toUpperCase();
        else if (key === "INTERVAL") out.interval = parseInt(val, 10) || 1;
        else if (key === "COUNT") out.count = parseInt(val, 10);
        else if (key === "UNTIL") out.until = parseDateTime({ value: val, params: {} }).date;
        else if (key === "BYDAY") out.byday = val.split(',');
    }
    return out;
}

function cloneWithStart(master, newStart) {
    var durationMs = (master.dtend && master.dtstart) ? (master.dtend.getTime() - master.dtstart.getTime()) : 0;
    var clone = {};
    for (var k in master) clone[k] = master[k];
    clone.dtstart = newStart;
    clone.dtend = new Date(newStart.getTime() + durationMs);
    clone.recurrenceId = newStart;
    return clone;
}

// Best-effort RRULE expansion supporting FREQ=DAILY/WEEKLY/MONTHLY/YEARLY,
// INTERVAL, COUNT, UNTIL and a simple weekday set (BYDAY) for WEEKLY. This is
// only a fallback for servers that ignore the CalDAV `expand` request; it is
// intentionally not a full RFC 5545 recurrence engine.
function expandRRule(master, rruleStr, exdates, overridesByTime, rangeStart, rangeEnd) {
    var rule = parseRRule(rruleStr);
    if (!master.dtstart || !rule.freq) return [];

    var exdateTimes = {};
    for (var e = 0; e < exdates.length; e++) exdateTimes[exdates[e].getTime()] = true;

    var results = [];
    var occCount = 0;
    var cursor = new Date(master.dtstart.getTime());
    var maxIterations = 2000;
    var iterations = 0;

    while (iterations++ < maxIterations) {
        if (rule.until && cursor > rule.until) break;
        if (rule.count && occCount >= rule.count) break;
        if (cursor >= rangeEnd) break;

        var candidateDates = [cursor];
        if (rule.freq === "WEEKLY" && rule.byday && rule.byday.length > 0) {
            candidateDates = weekdayOccurrencesForWeek(cursor, rule.byday);
        }

        for (var c = 0; c < candidateDates.length; c++) {
            var occStart = candidateDates[c];
            if (rule.until && occStart > rule.until) continue;
            occCount++;
            if (rule.count && occCount > rule.count) break;
            if (occStart < rangeStart || occStart >= rangeEnd) continue;
            if (exdateTimes[occStart.getTime()]) continue;
            var override = overridesByTime[occStart.getTime()];
            results.push(override || cloneWithStart(master, occStart));
        }

        cursor = advance(cursor, rule);
    }

    return results;
}

function weekdayOccurrencesForWeek(weekAnchor, byday) {
    var codes = {};
    for (var i = 0; i < WEEKDAY_CODES.length; i++) codes[WEEKDAY_CODES[i]] = i;
    var weekStart = new Date(weekAnchor);
    weekStart.setDate(weekStart.getDate() - weekStart.getDay());
    var out = [];
    for (var b = 0; b < byday.length; b++) {
        var code = byday[b].replace(/[+-]?\d*/, "");
        if (!(code in codes)) continue;
        var d = new Date(weekStart);
        d.setDate(d.getDate() + codes[code]);
        d.setHours(weekAnchor.getHours(), weekAnchor.getMinutes(), weekAnchor.getSeconds(), 0);
        out.push(d);
    }
    out.sort(function (a, b) { return a.getTime() - b.getTime(); });
    return out;
}

function advance(date, rule) {
    var d = new Date(date);
    switch (rule.freq) {
        case "DAILY": d.setDate(d.getDate() + rule.interval); break;
        case "WEEKLY": d.setDate(d.getDate() + 7 * rule.interval); break;
        case "MONTHLY": d.setMonth(d.getMonth() + rule.interval); break;
        case "YEARLY": d.setFullYear(d.getFullYear() + rule.interval); break;
        default: d.setDate(d.getDate() + 1);
    }
    return d;
}

// Produces the ICS text for a VTODO whose STATUS/COMPLETED/PERCENT-COMPLETE
// have been updated, by patching the original raw property lines. Used to
// PUT a completion toggle back without disturbing unrelated properties.
function patchTodoStatus(todo, completed) {
    var lines = (todo.rawLines || []).slice();
    var out = [];
    var sawStatus = false, sawCompleted = false, sawPercent = false;
    for (var i = 0; i < lines.length; i++) {
        var prop = parseLine(lines[i]);
        if (prop && prop.name === "STATUS") { continue; }
        if (prop && prop.name === "COMPLETED") { continue; }
        if (prop && prop.name === "PERCENT-COMPLETE") { continue; }
        out.push(lines[i]);
    }
    if (completed) {
        out.push("STATUS:COMPLETED");
        out.push("COMPLETED:" + formatDateTimeUTC(new Date()));
        out.push("PERCENT-COMPLETE:100");
    } else {
        out.push("STATUS:NEEDS-ACTION");
        out.push("PERCENT-COMPLETE:0");
    }
    return "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//KDE-Caldav//CalDAV Agenda//EN\nBEGIN:VTODO\n" +
           out.join("\n") + "\nEND:VTODO\nEND:VCALENDAR\n";
}

// Rewrites SUMMARY/DUE on an existing task's raw property lines, the same
// patch-in-place approach as patchTodoStatus above, so STATUS, PRIORITY,
// RELATED-TO and anything else already on the task survive an edit
// untouched instead of being dropped by rebuilding the object from
// scratch. `fields.due` is an optional Date; passing none removes it.
function patchTodoFields(todo, fields) {
    var lines = (todo.rawLines || []).slice();
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        var prop = parseLine(lines[i]);
        if (prop && (prop.name === "SUMMARY" || prop.name === "DUE")) continue;
        out.push(lines[i]);
    }
    out.push("SUMMARY:" + escapeText(fields.summary));
    if (fields.due) out.push("DUE;VALUE=DATE:" + formatDateStamp(fields.due));
    return "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//KDE-Caldav//CalDAV Agenda//EN\nBEGIN:VTODO\n" +
           out.join("\n") + "\nEND:VTODO\nEND:VCALENDAR\n";
}

// Rewrites SUMMARY/DTSTART/DTEND (and drops any DURATION in favor of an
// explicit DTEND) in a single-VEVENT ICS blob just fetched fresh via
// CalDAV.fetchEventResource, patching those specific lines rather than
// rebuilding the object - so LOCATION, DESCRIPTION, RRULE and anything
// else this app doesn't otherwise round-trip survive an edit untouched.
function patchEventFields(icsText, fields) {
    var lines = unfold(icsText).split("\n").map(function (l) { return l.replace(/\s+$/, ""); }).filter(function (l) { return l.length > 0; });
    var block = (splitComponents(lines, "VEVENT")[0] || []).slice();
    var out = [];
    for (var i = 0; i < block.length; i++) {
        var prop = parseLine(block[i]);
        if (prop && (prop.name === "SUMMARY" || prop.name === "DTSTART" || prop.name === "DTEND" || prop.name === "DURATION")) continue;
        out.push(block[i]);
    }
    out.push("SUMMARY:" + escapeText(fields.summary));
    if (fields.allDay) {
        out.push("DTSTART;VALUE=DATE:" + formatDateStamp(fields.start));
        out.push("DTEND;VALUE=DATE:" + formatDateStamp(fields.end));
    } else {
        out.push("DTSTART:" + formatLocalDateTimeStamp(fields.start));
        out.push("DTEND:" + formatLocalDateTimeStamp(fields.end));
    }
    return "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//KDE-Caldav//CalDAV Agenda//EN\nBEGIN:VEVENT\n" +
           out.join("\n") + "\nEND:VEVENT\nEND:VCALENDAR\n";
}

function formatDateStamp(date) {
    return date.getFullYear() + pad(date.getMonth() + 1) + pad(date.getDate());
}

function formatLocalDateTimeStamp(date) {
    return date.getFullYear() + pad(date.getMonth() + 1) + pad(date.getDate()) + "T" +
           pad(date.getHours()) + pad(date.getMinutes()) + pad(date.getSeconds());
}

// Builds a brand-new VTODO's ICS text for creation. `due` is an optional
// Date (treated as a DATE, not DATE-TIME - due dates don't need a time of
// day for this app's purposes). `parentUid` is optional, for creating a
// subtask under an existing task.
function buildVTodoIcs(opts) {
    var lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//KDE-Caldav//CalDAV Agenda//EN",
        "BEGIN:VTODO",
        "UID:" + opts.uid,
        "DTSTAMP:" + formatDateTimeUTC(new Date()),
        "SUMMARY:" + escapeText(opts.summary),
        "STATUS:NEEDS-ACTION",
        "PERCENT-COMPLETE:0"
    ];
    if (opts.due) lines.push("DUE;VALUE=DATE:" + formatDateStamp(opts.due));
    if (opts.parentUid) lines.push("RELATED-TO:" + opts.parentUid);
    lines.push("END:VTODO", "END:VCALENDAR", "");
    return lines.join("\n");
}

// Builds a brand-new VEVENT's ICS text for creation. `start`/`end` are
// Dates; when `allDay` is true they're written as DATE values (end is
// exclusive per RFC 5545, so callers should pass the day *after* the last
// all-day date), otherwise as floating (no TZID/UTC) DATE-TIME values in
// the desktop's local wall-clock time.
function buildVEventIcs(opts) {
    var lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//KDE-Caldav//CalDAV Agenda//EN",
        "BEGIN:VEVENT",
        "UID:" + opts.uid,
        "DTSTAMP:" + formatDateTimeUTC(new Date()),
        "SUMMARY:" + escapeText(opts.summary)
    ];
    if (opts.allDay) {
        lines.push("DTSTART;VALUE=DATE:" + formatDateStamp(opts.start));
        lines.push("DTEND;VALUE=DATE:" + formatDateStamp(opts.end));
    } else {
        lines.push("DTSTART:" + formatLocalDateTimeStamp(opts.start));
        lines.push("DTEND:" + formatLocalDateTimeStamp(opts.end));
    }
    if (opts.location) lines.push("LOCATION:" + escapeText(opts.location));
    lines.push("END:VEVENT", "END:VCALENDAR", "");
    return lines.join("\n");
}
