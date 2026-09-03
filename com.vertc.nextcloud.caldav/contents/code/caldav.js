.pragma library

// Thin CalDAV client for Nextcloud, built on QML's built-in XMLHttpRequest.
//
// IMPORTANT: Qt's QML XMLHttpRequest hardcodes an allow-list of HTTP methods
// (see QQmlXMLHttpRequestCtor::method_open in qtdeclarative) - GET, PUT,
// HEAD, POST, DELETE, OPTIONS, PROPFIND, PATCH - and throws a JS exception
// for anything else. REPORT, the method RFC 4791's calendar-query and
// calendar-multiget are built on, is *not* on that list, and there is no
// way to work around this client-side; it's enforced in Qt's C++, not
// something a request can talk its way past. So none of this can use a
// standard CalDAV REPORT.
//
// Instead:
//  - Events are fetched via SabreDAV's ICS export extension
//    (GET <calendar>?export&expand=1&start=..&end=..), which returns one
//    merged, already-expanded VCALENDAR blob for the whole range using a
//    plain GET. This is what Nextcloud (and other SabreDAV-based servers)
//    expose; it is not part of the base CalDAV spec, so this widget is
//    less portable to non-SabreDAV CalDAV servers than a REPORT-based
//    client would be.
//  - Tasks are fetched via PROPFIND (Depth: 1, requesting getetag and
//    getcontenttype) to list the collection's members and pick out just
//    the ones SabreDAV's getcontenttype reports as "component=VTODO",
//    followed by an individual GET per matching resource. This is
//    needed (rather than also using ?export) because task completion
//    toggling has to PUT back to a *specific* resource's href with an
//    If-Match on its etag, and the merged export blob doesn't preserve
//    per-object identity.
//
// Discovery (PROPFIND on the calendar-home) and the completion-toggle
// write-back (PUT) both already only use allow-listed methods and are
// unaffected by any of this.

function normalizeServerUrl(url) {
    var trimmed = (url || "").trim().replace(/\/+$/, "");
    if (!/^https?:\/\//i.test(trimmed)) {
        trimmed = "https://" + trimmed;
    }
    return trimmed;
}

function originOf(serverUrl) {
    var m = normalizeServerUrl(serverUrl).match(/^(https?:\/\/[^\/]+)/i);
    return m ? m[1] : normalizeServerUrl(serverUrl);
}

function resolveHref(serverUrl, href) {
    if (/^https?:\/\//i.test(href)) return href;
    return originOf(serverUrl) + href;
}

function calendarHomeUrl(serverUrl, username) {
    return normalizeServerUrl(serverUrl) + "/remote.php/dav/calendars/" + encodeURIComponent(username) + "/";
}

function setAuthHeader(xhr, username, password) {
    xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(username + ":" + password));
}

function describeHttpError(status) {
    if (status === 0) return "network"; // unreachable host, TLS failure, timeout, ...
    if (status === 401 || status === 403) return "auth";
    if (status === 404) return "notfound";
    return "http:" + status;
}

function stripNamespacePrefixes(xml) {
    return xml.replace(/<\/?[a-zA-Z0-9]+:/g, function (m) { return m[1] === "/" ? "</" : "<"; });
}

function decodeXmlEntities(text) {
    return text
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"').replace(/&apos;/g, "'")
        .replace(/&#(\d+);/g, function (_, d) { return String.fromCharCode(parseInt(d, 10)); })
        .replace(/&amp;/g, "&");
}

function extractAll(xml, tag) {
    var re = new RegExp("<" + tag + "(?:\\s[^>]*)?>([\\s\\S]*?)<\\/" + tag + ">", "gi");
    var out = [];
    var m;
    while ((m = re.exec(xml)) !== null) out.push(m[1]);
    return out;
}

function extractFirst(xml, tag) {
    var all = extractAll(xml, tag);
    return all.length > 0 ? all[0] : null;
}

function sendRequest(method, url, username, password, headers, body, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open(method, url, true);
    setAuthHeader(xhr, username, password);
    for (var h in headers) xhr.setRequestHeader(h, headers[h]);
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status >= 200 && xhr.status < 300 || xhr.status === 207) {
            callback(null, xhr);
        } else {
            callback(describeHttpError(xhr.status), xhr);
        }
    };
    xhr.onerror = function () { callback("network", xhr); };
    // xhr.send(x) stringifies whatever it's given - even null becomes the
    // literal text "null" - so a bodyless request (GET, PROPFIND without a
    // filter body, ...) must call send() with no arguments at all.
    if (body) xhr.send(body); else xhr.send();
}

// callback(error, calendars) where calendars is an array of
// { href, displayName, color, kinds: ["VEVENT", "VTODO", ...] }
function discoverCalendars(serverUrl, username, password, callback) {
    var homeUrl = calendarHomeUrl(serverUrl, username);
    var body = '<?xml version="1.0" encoding="utf-8" ?>' +
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:ic="http://apple.com/ns/ical/">' +
        '<d:prop><d:resourcetype/><d:displayname/><ic:calendar-color/>' +
        '<c:supported-calendar-component-set/></d:prop></d:propfind>';
    sendRequest("PROPFIND", homeUrl, username, password, { "Depth": "1", "Content-Type": "application/xml; charset=utf-8" }, body,
        function (err, xhr) {
            if (err) { callback(err, null); return; }
            try {
                callback(null, parseCalendarHome(xhr.responseText));
            } catch (e) {
                callback("parse", null);
            }
        });
}

function parseCalendarHome(xmlText) {
    var xml = stripNamespacePrefixes(xmlText);
    var responses = extractAll(xml, "response");
    var calendars = [];
    for (var i = 0; i < responses.length; i++) {
        var block = responses[i];
        var resourceType = extractFirst(block, "resourcetype") || "";
        if (resourceType.indexOf("<calendar") === -1) continue;
        var href = extractFirst(block, "href");
        if (!href) continue;
        var displayName = decodeXmlEntities(extractFirst(block, "displayname") || "");
        var colorRaw = extractFirst(block, "calendar-color");
        var color = colorRaw ? colorRaw.trim().substring(0, 7) : null;
        var compSetBlock = extractFirst(block, "supported-calendar-component-set") || "";
        var kinds = [];
        if (compSetBlock.indexOf('name="VEVENT"') !== -1) kinds.push("VEVENT");
        if (compSetBlock.indexOf('name="VTODO"') !== -1) kinds.push("VTODO");
        if (kinds.length === 0) kinds.push("VEVENT");
        calendars.push({ href: decodeXmlEntities(href), displayName: displayName || href, color: color, kinds: kinds });
    }
    return calendars;
}

// callback(error, items) where items is [{ href, etag, icsText }] - a
// single-element array, since ?export returns one merged VCALENDAR for the
// whole range rather than a per-resource listing. etag is null: individual
// event resources aren't identifiable from this response, but nothing here
// needs to write events back, only display them.
function fetchEvents(serverUrl, username, password, calendarHref, rangeStart, rangeEnd, callback) {
    var url = resolveHref(serverUrl, calendarHref);
    var sep = url.indexOf("?") === -1 ? "?" : "&";
    url += sep + "export&expand=1" +
        "&start=" + Math.floor(rangeStart.getTime() / 1000) +
        "&end=" + Math.floor(rangeEnd.getTime() / 1000);
    sendRequest("GET", url, username, password, { "Accept": "text/calendar" }, null, function (err, xhr) {
        if (err) { callback(err, null); return; }
        callback(null, [{ href: calendarHref, etag: null, icsText: xhr.responseText }]);
    });
}

// callback(error, items) where items is [{ href, etag, icsText }], one per
// task. Every VTODO in the collection is returned; completion/due-date
// filtering happens client-side since CalDAV time-range semantics for
// VTODO are awkward, and ?export drops start/end filtering support for
// VTODO entirely (see the file-level comment).
//
// Two-step: PROPFIND (Depth: 1) lists every member of the collection with
// its etag and getcontenttype, which SabreDAV reports as e.g.
// "text/calendar; component=VTODO" per resource - filtering on that avoids
// downloading every VEVENT in a mixed calendar just to discard it. Each
// matching resource is then fetched individually with a plain GET.
function fetchTodos(serverUrl, username, password, calendarHref, callback) {
    var url = resolveHref(serverUrl, calendarHref);
    var body = '<?xml version="1.0" encoding="utf-8" ?>' +
        '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:getcontenttype/></d:prop></d:propfind>';
    sendRequest("PROPFIND", url, username, password, { "Depth": "1", "Content-Type": "application/xml; charset=utf-8" }, body,
        function (err, xhr) {
            if (err) { callback(err, null); return; }
            var entries;
            try {
                entries = parseTodoListing(xhr.responseText);
            } catch (e) {
                callback("parse", null);
                return;
            }
            if (entries.length === 0) { callback(null, []); return; }

            var results = [];
            var pending = entries.length;
            var firstErr = null;
            entries.forEach(function (entry) {
                var itemUrl = resolveHref(serverUrl, entry.href);
                sendRequest("GET", itemUrl, username, password, { "Accept": "text/calendar" }, null, function (getErr, itemXhr) {
                    if (getErr) {
                        firstErr = firstErr || getErr;
                    } else {
                        results.push({ href: entry.href, etag: entry.etag, icsText: itemXhr.responseText });
                    }
                    pending--;
                    if (pending <= 0) callback(results.length > 0 ? null : firstErr, results);
                });
            });
        });
}

function parseTodoListing(xmlText) {
    var xml = stripNamespacePrefixes(xmlText);
    var responses = extractAll(xml, "response");
    var out = [];
    for (var i = 0; i < responses.length; i++) {
        var block = responses[i];
        var contentType = extractFirst(block, "getcontenttype") || "";
        if (contentType.toUpperCase().indexOf("VTODO") === -1) continue;
        var href = extractFirst(block, "href");
        if (!href) continue;
        var etag = extractFirst(block, "getetag");
        out.push({ href: decodeXmlEntities(href), etag: etag ? decodeXmlEntities(etag) : null });
    }
    return out;
}

// Writes back a full ICS body (VEVENT or VTODO, as produced by ical.js's
// patchTodoStatus/patchTodoFields/patchEventFields) to an existing
// resource, with an If-Match on the last known etag so a concurrent edit
// elsewhere is refused rather than silently overwritten.
function updateResource(serverUrl, username, password, href, etag, icsText, callback) {
    var url = resolveHref(serverUrl, href);
    var headers = { "Content-Type": "text/calendar; charset=utf-8" };
    if (etag) headers["If-Match"] = etag;
    sendRequest("PUT", url, username, password, headers, icsText, function (err) {
        callback(err);
    });
}

// Deletes an existing calendar object resource, with an If-Match on the
// last known etag so a concurrent edit elsewhere is refused instead of
// deleting out from under it.
function deleteResource(serverUrl, username, password, href, etag, callback) {
    var url = resolveHref(serverUrl, href);
    var headers = {};
    if (etag) headers["If-Match"] = etag;
    sendRequest("DELETE", url, username, password, headers, null, function (err) {
        callback(err);
    });
}

// Fetches a single event's own resource by UID, guessing the same
// <calendarHref><uid>.ics naming convention createResource uses when
// creating one. Needed before editing/deleting an event: fetchEvents()
// above uses SabreDAV's ?export extension for display, which returns one
// merged blob with no per-resource href or etag (see the file-level
// comment) - there is no per-object identity to write back to until this
// resolves the resource fresh. callback(error, { href, etag, icsText }).
// A servers/clients that name event resources differently than
// <uid>.ics will 404 here - surfaced as a plain "notfound" error rather
// than guessed around further.
function fetchEventResource(serverUrl, username, password, calendarHref, uid, callback) {
    var href = calendarHref + (calendarHref.charAt(calendarHref.length - 1) === "/" ? "" : "/") + uid + ".ics";
    var url = resolveHref(serverUrl, href);
    sendRequest("GET", url, username, password, { "Accept": "text/calendar" }, null, function (err, xhr) {
        if (err) { callback(err, null); return; }
        var etag = null;
        try { etag = xhr.getResponseHeader("ETag"); } catch (e) { /* no header support, fine without */ }
        callback(null, { href: href, etag: etag, icsText: xhr.responseText });
    });
}

// Creates a brand-new calendar object resource at <calendarHref><uid>.ics.
// If-None-Match: * asks the server to refuse the write if a resource with
// that name already exists, rather than silently overwriting it - shouldn't
// ever trigger given uid is a fresh generateUid(), but costs nothing.
function createResource(serverUrl, username, password, calendarHref, uid, icsText, callback) {
    var href = calendarHref + (calendarHref.charAt(calendarHref.length - 1) === "/" ? "" : "/") + uid + ".ics";
    var url = resolveHref(serverUrl, href);
    var headers = { "Content-Type": "text/calendar; charset=utf-8", "If-None-Match": "*" };
    sendRequest("PUT", url, username, password, headers, icsText, function (err) {
        callback(err, href);
    });
}

// --- Nextcloud Login Flow v2 --------------------------------------------
// https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html#login-flow-v2
//
// This is how the config UI obtains credentials instead of asking the user
// to type their password (or paste an app password) into the widget: the
// user completes sign-in in their actual browser (so it works with 2FA/SSO
// and the real account password never touches this code), and Nextcloud
// hands back a username + app password pair. That pair is then used the
// same way a manually-created app password would be — plain HTTP Basic
// Auth against the CalDAV endpoint, via the functions above. This is *not*
// generic OAuth2; Nextcloud does not require (or expect) a registered
// client id/secret for it.

// callback(error, { login, poll: { token, endpoint } }). `login` is the URL
// to open in a browser; `poll` is what to hand to pollLoginFlow.
function startLoginFlow(serverUrl, callback) {
    var url = normalizeServerUrl(serverUrl) + "/index.php/login/v2";
    var xhr = new XMLHttpRequest();
    xhr.open("POST", url, true);
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status !== 200) { callback(describeHttpError(xhr.status), null); return; }
        try {
            var data = JSON.parse(xhr.responseText);
            if (!data || !data.poll || !data.login) { callback("parse", null); return; }
            callback(null, data);
        } catch (e) {
            callback("parse", null);
        }
    };
    xhr.onerror = function () { callback("network", null); };
    xhr.send();
}

// Polls once. callback(error, result): error is null with a populated
// result { server, loginName, appPassword } once the user has finished
// signing in; error is "pending" while still waiting (poll again after a
// delay); any other error string means give up.
function pollLoginFlow(pollEndpoint, pollToken, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", pollEndpoint, true);
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status === 404) { callback("pending", null); return; }
        if (xhr.status !== 200) { callback(describeHttpError(xhr.status), null); return; }
        try {
            var data = JSON.parse(xhr.responseText);
            if (!data || !data.appPassword || !data.loginName) { callback("parse", null); return; }
            callback(null, data);
        } catch (e) {
            callback("parse", null);
        }
    };
    xhr.onerror = function () { callback("network", null); };
    xhr.send("token=" + encodeURIComponent(pollToken));
}
