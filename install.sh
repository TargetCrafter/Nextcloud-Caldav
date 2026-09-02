#!/usr/bin/env bash
# Installs or upgrades the CalDAV Agenda plasmoid for the current user.
#
# Usage:
#   ./install.sh                                    # auto-detect (see below)
#   ./install.sh com.github.targetcrafter.kdecaldav.plasmoid   # install a specific package
set -euo pipefail

PLUGIN_ID="com.github.targetcrafter.kdecaldav"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "kpackagetool6 not found. This widget requires KDE Plasma 6." >&2
    exit 1
fi

# With no argument, auto-detect what's next to this script: a full source
# checkout (contents/, metadata.json - i.e. this script run from a git
# clone) takes priority, then a downloaded .plasmoid file sitting alongside
# it (the common case if you grabbed install.sh and the .plasmoid
# separately from the Releases page into the same folder, e.g. ~/Downloads).
if [ -n "${1:-}" ]; then
    TARGET="$1"
elif [ -e "$SCRIPT_DIR/$PLUGIN_ID/metadata.json" ]; then
    TARGET="$SCRIPT_DIR/$PLUGIN_ID"
elif [ -e "$SCRIPT_DIR/$PLUGIN_ID.plasmoid" ]; then
    TARGET="$SCRIPT_DIR/$PLUGIN_ID.plasmoid"
else
    echo "Couldn't find anything to install next to this script." >&2
    echo >&2
    echo "Either:" >&2
    echo "  - run this from a full git clone of the repo (so $PLUGIN_ID/ sits next to it), or" >&2
    echo "  - download $PLUGIN_ID.plasmoid from" >&2
    echo "    https://github.com/TargetCrafter/KDE-Caldav/releases into the same folder" >&2
    echo "    as this script, or" >&2
    echo "  - pass the path explicitly: ./install.sh /path/to/$PLUGIN_ID.plasmoid" >&2
    exit 1
fi

if [ ! -e "$TARGET" ]; then
    echo "$TARGET not found." >&2
    exit 1
fi

if kpackagetool6 --type Plasma/Applet --show "$PLUGIN_ID" >/dev/null 2>&1; then
    echo "Upgrading existing installation from $TARGET ..."
    kpackagetool6 --type Plasma/Applet --upgrade "$TARGET"
else
    echo "Installing from $TARGET ..."
    kpackagetool6 --type Plasma/Applet --install "$TARGET"
fi

echo
echo "Done. Add it via: right-click desktop or panel -> Add Widgets... -> search 'CalDAV Agenda'."
echo "If it doesn't show up right away, restart Plasma: plasmashell --replace &"
