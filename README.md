# CalDAV Agenda

A KDE Plasma 6 widget that shows your upcoming Nextcloud (or any CalDAV
server's) events and tasks on the desktop or panel, with a clean Kirigami
interface: events and tasks grouped by day, overdue tasks called out
separately, and one-click completion for to-dos.

Built as a lighter-weight alternative to
[KAgenda](https://github.com/aamaral14/KAgenda): plain HTTP Basic Auth with
a Nextcloud *app password* instead of an OAuth2 + Python helper flow, and no
compiled backend — it's a pure QML plasmoid you can install with
`kpackagetool6`.

## Features

- Auto-discovers every calendar and task list on your Nextcloud account
- Events grouped by day ("Today", "Tomorrow", weekday names), with
  recurring events expanded server-side
- Tasks (VTODO) grouped into Overdue / due-today / due-later / no due date,
  with a checkbox to mark them done directly from the widget
- Panel view shows the next event's countdown, today's event count, or just
  an icon — your choice
- Per-calendar color coding
- Configurable look-ahead window and refresh interval

## Installing

```sh
git clone https://github.com/TargetCrafter/KDE-Caldav.git
cd KDE-Caldav
./install.sh
```

That runs `kpackagetool6 --type Plasma/Applet --install
com.github.targetcrafter.kdecaldav`. Then add it from **right-click desktop
or panel → Add Widgets… → search "CalDAV Agenda"**.

To update after pulling new changes, run `./install.sh` again (it detects
the existing install and upgrades it).

To remove it: `kpackagetool6 --type Plasma/Applet --remove com.github.targetcrafter.kdecaldav`

## Setting up your account

1. Open the widget's settings (right-click → Configure…).
2. **Server address**: your Nextcloud URL, e.g. `https://cloud.example.com`
   (just the base URL — the widget appends `/remote.php/dav/...` itself).
3. **Username**: your Nextcloud login name.
4. **App password**: don't use your real account password. Generate a
   scoped, revocable one instead: Nextcloud → Settings → Security →
   *Devices & sessions* → **Create new app password**.
5. Click **Find calendars** and tick which calendars/task lists to show.

## How it talks to CalDAV

- Discovery: `PROPFIND` on `/remote.php/dav/calendars/<username>/`.
- Events: `REPORT` calendar-query with a server-side `<C:expand>` range, so
  recurring events don't need to be expanded client-side (Nextcloud's
  sabre/dav backend supports this). A best-effort client-side RRULE
  expander (daily/weekly/monthly/yearly, weekday sets) is included as a
  fallback for servers that ignore `expand`.
- Tasks: `REPORT` calendar-query for `VTODO`, filtered/grouped client-side.
- Marking a task done: `PUT` with `If-Match` on the stored ETag, so a
  conflicting edit made elsewhere is refused instead of silently
  overwritten.

## Known limitations

- **Timezones**: event times carrying a `TZID` (rather than UTC) are
  treated as wall-clock time in the desktop's local timezone. There's no
  bundled IANA timezone database, so a calendar authored in a different
  timezone than your desktop will show shifted times. Nextcloud's
  server-side `expand` normally returns UTC times, which sidesteps this for
  most setups.
- **Credential storage**: the app password is stored via KConfigXT's
  `Password` entry type, which KDE Frameworks backs with KWallet when one
  is available on the system; otherwise it falls back to the plasmoid's
  regular (user-readable-only) config file. Using an app password rather
  than your account password limits the blast radius either way.
- Discovery assumes the standard Nextcloud CalDAV layout
  (`/remote.php/dav/calendars/<username>/…`); servers with a different
  principal/calendar-home layout aren't auto-discovered.
- No event/task creation or editing beyond the done/not-done toggle.

## Package layout

```
com.github.targetcrafter.kdecaldav/
  metadata.json
  contents/
    ui/          QML: main.qml, Compact/FullRepresentation, delegates, config pages
    config/      main.xml (KConfigXT schema), config.qml (settings page list)
    code/        caldav.js (HTTP/WebDAV), ical.js (iCalendar parsing/RRULE), dateutils.js
```

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
