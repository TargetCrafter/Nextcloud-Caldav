.pragma library

// Pure date/time helpers. Deliberately free of i18n() calls: .pragma library
// scripts run in an isolated JS context that does not get the QML engine's
// translation globals, so all user-facing label text is composed in QML,
// using the plain data (Date objects, day offsets, booleans) returned here.

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date, days) {
    var d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
}

function startOfMonth(date) {
    return new Date(date.getFullYear(), date.getMonth(), 1);
}

// Always returns the 1st of the resulting month (months is a count, not a
// day-preserving offset) - callers that need a specific day within it add
// that separately.
function addMonths(date, months) {
    return new Date(date.getFullYear(), date.getMonth() + months, 1);
}

function daysBetween(a, b) {
    var msPerDay = 24 * 60 * 60 * 1000;
    return Math.round((startOfDay(b).getTime() - startOfDay(a).getTime()) / msPerDay);
}

function isSameDay(a, b) {
    return a.getFullYear() === b.getFullYear() &&
           a.getMonth() === b.getMonth() &&
           a.getDate() === b.getDate();
}

// Stable sortable key (YYYY-MM-DD) for grouping list entries by day.
function dayKey(date) {
    var y = date.getFullYear();
    var m = ("0" + (date.getMonth() + 1)).slice(-2);
    var d = ("0" + date.getDate()).slice(-2);
    return y + "-" + m + "-" + d;
}

// Day offset of `date` relative to `now` (0 = today, 1 = tomorrow, -1 = yesterday, ...).
function dayOffset(date, now) {
    return daysBetween(now || new Date(), date);
}

function isOverdue(dueDate, now) {
    return dueDate.getTime() < (now || new Date()).getTime();
}

// Minutes between now and date; negative means date is in the past.
function minutesUntil(date, now) {
    return (date.getTime() - (now || new Date()).getTime()) / 60000;
}
