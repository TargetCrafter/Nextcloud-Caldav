.pragma library

// Thin CalDAV client for Nextcloud, built on QML's built-in XMLHttpRequest.
// Speaks just enough WebDAV/CalDAV (RFC 4791) to discover calendar/task-list
// collections under a user's calendar-home and run calendar-query REPORTs
// against them. Parsing of the returned iCalendar payloads happens in
// ical.js; this module only deals with HTTP + XML plumbing.

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

function toUtcStamp(date) {
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    return date.getUTCFullYear() + pad(date.getUTCMonth() + 1) + pad(date.getUTCDate()) + "T" +
           pad(date.getUTCHours()) + pad(date.getUTCMinutes()) + pad(date.getUTCSeconds()) + "Z";
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
    xhr.send(body);
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

// callback(error, items) where items is [{ href, etag, icsText }]
function fetchEvents(serverUrl, username, password, calendarHref, rangeStart, rangeEnd, callback) {
    var url = resolveHref(serverUrl, calendarHref);
    var startStamp = toUtcStamp(rangeStart);
    var endStamp = toUtcStamp(rangeEnd);
    var body = '<?xml version="1.0" encoding="utf-8" ?>' +
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' +
        '<d:prop><d:getetag/><c:calendar-data><c:expand start="' + startStamp + '" end="' + endStamp + '"/></c:calendar-data></d:prop>' +
        '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">' +
        '<c:time-range start="' + startStamp + '" end="' + endStamp + '"/>' +
        '</c:comp-filter></c:comp-filter></c:filter>' +
        '</c:calendar-query>';
    runCalendarQuery(url, username, password, body, callback);
}

// callback(error, items) where items is [{ href, etag, icsText }]. Fetches
// every VTODO in the collection; completion/due-date filtering happens
// client-side since CalDAV time-range semantics for VTODO are awkward.
function fetchTodos(serverUrl, username, password, calendarHref, callback) {
    var url = resolveHref(serverUrl, calendarHref);
    var body = '<?xml version="1.0" encoding="utf-8" ?>' +
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' +
        '<d:prop><d:getetag/><c:calendar-data/></d:prop>' +
        '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VTODO"/></c:comp-filter></c:filter>' +
        '</c:calendar-query>';
    runCalendarQuery(url, username, password, body, callback);
}

function runCalendarQuery(url, username, password, body, callback) {
    sendRequest("REPORT", url, username, password, { "Depth": "1", "Content-Type": "application/xml; charset=utf-8" }, body,
        function (err, xhr) {
            if (err) { callback(err, null); return; }
            try {
                callback(null, parseMultistatusCalendarData(xhr.responseText));
            } catch (e) {
                callback("parse", null);
            }
        });
}

function parseMultistatusCalendarData(xmlText) {
    var xml = stripNamespacePrefixes(xmlText);
    var responses = extractAll(xml, "response");
    var items = [];
    for (var i = 0; i < responses.length; i++) {
        var block = responses[i];
        var href = extractFirst(block, "href");
        var etag = extractFirst(block, "getetag");
        var data = extractFirst(block, "calendar-data");
        if (!href || !data) continue;
        items.push({ href: decodeXmlEntities(href), etag: etag ? decodeXmlEntities(etag) : null, icsText: decodeXmlEntities(data) });
    }
    return items;
}

// Writes back a full VTODO ICS body (as produced by ical.js's
// patchTodoStatus) with an If-Match on the last known etag so a concurrent
// edit elsewhere is refused rather than silently overwritten.
function putTodo(serverUrl, username, password, todoHref, etag, icsText, callback) {
    var url = resolveHref(serverUrl, todoHref);
    var headers = { "Content-Type": "text/calendar; charset=utf-8" };
    if (etag) headers["If-Match"] = etag;
    sendRequest("PUT", url, username, password, headers, icsText, function (err) {
        callback(err);
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
