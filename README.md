# CalDAV Agenda

A KDE Plasma 6 widget that shows your upcoming Nextcloud (or any CalDAV
server's) events and tasks on the desktop or panel, with a clean Kirigami
interface: events and tasks grouped by day, overdue tasks called out
separately, and one-click completion for to-dos.

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
  with a checkbox to mark them done directly from the widget
- Panel view shows the next event's countdown, today's event count, or just
  an icon — your choice
- Per-calendar color coding
- Configurable look-ahead window and refresh interval

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
- **Everything else is plain CalDAV** over HTTP Basic Auth using that
  username/app-password pair:
  - Discovery: `PROPFIND` on `/remote.php/dav/calendars/<username>/`.
  - Events: `REPORT` calendar-query with a server-side `<C:expand>` range,
    so recurring events don't need to be expanded client-side (Nextcloud's
    sabre/dav backend supports this). A best-effort client-side RRULE
    expander (daily/weekly/monthly/yearly, weekday sets) is included as a
    fallback for servers that ignore `expand`.
  - Tasks: `REPORT` calendar-query for `VTODO`, filtered/grouped
    client-side.
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
- No event/task creation or editing beyond the done/not-done toggle.

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
