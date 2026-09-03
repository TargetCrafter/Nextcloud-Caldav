# CalDAV Agenda

A KDE Plasma 6 widget that shows your upcoming Nextcloud events and tasks
on the desktop or panel, with a clean Kirigami interface: events and tasks
grouped by day, overdue tasks called out separately, and one-click
completion for to-dos.

Built as a lighter-weight alternative to
[KAgenda](https://github.com/aamaral14/KAgenda): sign-in happens in your
actual browser via Nextcloud's *Login Flow v2* instead of an OAuth2 client
registration + Python helper process, and there's no compiled backend at
all — it's a pure QML plasmoid you can install from a single `.plasmoid`
file or with `kpackagetool6`.

## Features

- Auto-discovers every calendar and task list on your Nextcloud account
- Events grouped by day ("Today", "Tomorrow", weekday names), with
  recurring events expanded server-side
- Tasks (VTODO) grouped into Overdue / due-today / due-later / no due date,
  with a checkbox to mark them done directly from the widget, and subtasks
  (linked via `RELATED-TO`, e.g. from Nextcloud Tasks) shown indented under
  their parent
- Quick-add for both events and tasks, and edit or delete an existing one
  (single, non-recurring events only), right from the widget
- Each event/task renders as its own card with a hover highlight and a
  calendar-color accent bar, so items are easy to tell apart at a glance
- Panel view shows the next event's countdown, today's event count, or just
  an icon — your choice
- Per-calendar color coding
- Configurable look-ahead window and refresh interval
- Restrict a widget instance to events only, tasks only, or both combined —
  useful for placing separate calendar and to-do widgets side by side
- Optional month-calendar layout (in place of the agenda list), with colored
  dots marking days that have events, a Today button, and click-to-inspect
  days
- New-item date fields follow your system's day/month order

## Multiple widgets: separate calendar and to-do lists

Each widget instance has its own **Show** setting (Configure… → Appearance):
*Events and tasks*, *Events only*, or *Tasks only*. Add the widget to your
panel or desktop twice and set one instance to Events only and the other to
Tasks only to get separate calendar and to-do widgets, each still backed by
the same Nextcloud account and calendar selection.

## Installing

### Option A: a `.plasmoid` file (no terminal needed)

Grab `com.github.targetcrafter.kdecaldav.plasmoid` from the
[Releases](https://github.com/TargetCrafter/KDE-Caldav/releases) page (built
automatically by CI for each tagged version), then either:

- **Right-click the desktop or a panel → Add Widgets… → Get New Widgets…
  → Install Widget From Local File…**, and pick the downloaded file, or
- run `kpackagetool6 --type Plasma/Applet --install
  com.github.targetcrafter.kdecaldav.plasmoid` from a terminal.

To build that file yourself from a checkout instead of downloading it, run
`./package.sh` — it produces
`com.github.targetcrafter.kdecaldav.plasmoid` in the repo root, which you
can then install the same way (or via `./install.sh
com.github.targetcrafter.kdecaldav.plasmoid`).

### Option B: from source

```sh
git clone https://github.com/TargetCrafter/KDE-Caldav.git
cd KDE-Caldav
./install.sh
```

Either way, add the widget from **right-click desktop or panel → Add
Widgets… → search "CalDAV Agenda"**.

To update after pulling new changes, run `./install.sh` again (it detects
the existing install and upgrades it either from source or from a
`.plasmoid` file you pass as an argument).

To remove it: `kpackagetool6 --type Plasma/Applet --remove com.github.targetcrafter.kdecaldav`

## Setting up your account

1. Open the widget's settings (right-click → Configure…).
2. **Server address**: your Nextcloud URL, e.g. `https://cloud.example.com`
   (just the base URL — the widget appends `/remote.php/dav/...` itself).
3. Click **Log in with Nextcloud…**. This opens your default browser to
   Nextcloud's own sign-in page (so it works with 2FA, SSO, whatever your
   instance uses) using [Login Flow
   v2](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html#login-flow-v2)
   — the same mechanism the official desktop and mobile clients use. Your
   account password is typed into Nextcloud's own page, never into the
   widget. Once you approve the device in the browser, the widget picks up
   a username + scoped app password automatically.
   - No browser access, or the server doesn't support it? Use **Sign in
     manually instead…** to enter a username and an app password you
     generate yourself: Nextcloud → Settings → Security → *Devices &
     sessions* → **Create new app password**.
4. Click **Find calendars** (this runs automatically after browser sign-in)
   and tick which calendars/task lists to show.

## How it talks to Nextcloud

- **Sign-in**: `POST /index.php/login/v2` starts the flow and returns a
  browser URL plus a poll token; the widget opens the URL with
  `Qt.openUrlExternally` and polls the returned endpoint every couple of
  seconds until Nextcloud hands back `{ server, loginName, appPassword }`.
  That app password is exactly what you'd get from *Create new app
  password* by hand — it's not a generic OAuth2 access/refresh token, so
  there's no client registration, redirect URI, or token refresh to manage.
- **Everything else is CalDAV/WebDAV** over HTTP Basic Auth using that
  username/app-password pair — but with one hard constraint: Qt's QML
  `XMLHttpRequest` only allows `GET, PUT, HEAD, POST, DELETE, OPTIONS,
  PROPFIND, PATCH` and throws a JS exception for anything else, including
  `REPORT` — the method RFC 4791's `calendar-query`/`calendar-multiget`
  (the standard way a CalDAV client fetches events and tasks) is built on.
  This is enforced in Qt's C++, not something a request can work around, so
  a pure-QML plasmoid genuinely cannot issue a standards-based CalDAV
  query. Instead:
  - Discovery: `PROPFIND` on `/remote.php/dav/calendars/<username>/`.
  - Events: `GET <calendar>?export&expand=1&start=..&end=..` — SabreDAV's
    (Nextcloud's CalDAV backend) built-in ICS-export extension, which
    returns one already-expanded VCALENDAR blob for the date range using a
    plain GET. This is a SabreDAV/Nextcloud extension, not part of the base
    CalDAV spec — a non-SabreDAV CalDAV server likely won't support it,
    which is why this widget is Nextcloud-specific rather than "any CalDAV
    server."
  - Tasks: `PROPFIND` (Depth: 1) lists the calendar's members with their
    ETag and content-type, filtered client-side to the ones SabreDAV
    reports as `component=VTODO`, then a plain `GET` per matching task.
    Two steps rather than one `GET ?export`, because marking a task done
    needs a specific resource's href + ETag to `PUT` back to, and the
    merged export blob doesn't preserve that.
  - Marking a task done: `PUT` with `If-Match` on the stored ETag, so a
    conflicting edit made elsewhere is refused instead of silently
    overwritten.
  - A best-effort client-side RRULE expander (daily/weekly/monthly/yearly,
    weekday sets) still exists in `ical.js` as a fallback for any VEVENT
    that reaches the parser with an un-expanded `RRULE` still attached.

## Known limitations

- **Nextcloud-specific**: fetching relies on SabreDAV's `?export`
  extension (see above), not the base CalDAV `REPORT` method. It should
  work against any SabreDAV-based server (Nextcloud, ownCloud) but not
  against CalDAV servers that aren't SabreDAV-based.
- **Timezones**: event times are expanded server-side and returned in UTC
  by the `?export` endpoint, so this mostly isn't an issue for events. A
  task (VTODO) due date carrying a `TZID` (rather than UTC) is still
  treated as wall-clock time in the desktop's local timezone, since
  there's no bundled IANA timezone database — a task due date authored in
  a different timezone than your desktop may show a shifted time.
- **Credential storage**: the app password (whether obtained via browser
  sign-in or entered manually) is stored via KConfigXT's `Password` entry
  type, which KDE Frameworks backs with KWallet when one is available on
  the system; otherwise it falls back to the plasmoid's regular
  (user-readable-only) config file. Either way it's a scoped, individually
  revocable app password, never your actual account password.
- Login Flow v2 requires the widget to poll a plain HTTP(S) endpoint on
  your Nextcloud server and to be able to launch a browser via
  `xdg-open`/`Qt.openUrlExternally`; a purely headless/browser-less
  desktop needs the manual app-password fallback instead.
- Discovery assumes the standard Nextcloud CalDAV layout
  (`/remote.php/dav/calendars/<username>/…`); servers with a different
  principal/calendar-home layout aren't auto-discovered.
- Creating, editing, and deleting events/tasks is supported (hover an item
  for the edit icon, or use the "+" button to create one). Date/time entry
  is plain text fields following your system's date order, not a picker
  widget. Creating a task as a subtask of another isn't exposed in the UI
  (only reading and indenting existing subtasks is).
- **Recurring events can't be edited or deleted from the widget** - only
  single, non-recurring events get the edit icon. Which occurrence(s) an
  edit or delete should apply to (this one, this and future, or the whole
  series) is a real feature in its own right that a simple PUT/DELETE
  can't safely guess at; use Nextcloud's own web UI or client for those.
- Editing/deleting an event resolves its actual CalDAV resource by
  guessing the `<calendar>/<uid>.ics` naming convention this widget (and
  SabreDAV/Nextcloud's own clients) use when creating one - an event
  created by a client that names resources differently will fail to
  resolve, surfaced as a clear "server address not found"-style error
  rather than silently doing nothing.
- The month-calendar layout shows events only (no task due dates), and
  isn't available when a widget instance is set to Tasks only. Browsing to
  a different month issues its own fetch scoped to that month, separate
  from the agenda list's look-ahead window.

## Package layout

```
com.github.targetcrafter.kdecaldav/
  metadata.json
  contents/
    ui/          QML: main.qml, Compact/FullRepresentation, delegates, config pages
    config/      main.xml (KConfigXT schema), config.qml (settings page list)
    code/        caldav.js (HTTP/WebDAV + Login Flow v2), ical.js (parsing/RRULE), dateutils.js
install.sh        installs/upgrades from source or a .plasmoid file
package.sh         builds com.github.targetcrafter.kdecaldav.plasmoid
.github/workflows/release.yml   builds and attaches the .plasmoid on a tagged push
```

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
