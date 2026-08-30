#!/usr/bin/env bash
# Installs or upgrades the CalDAV Agenda plasmoid for the current user.
#
# Usage:
#   ./install.sh                                    # install from source
#   ./install.sh com.github.targetcrafter.kdecaldav.plasmoid   # install a built package
set -euo pipefail

PLUGIN_ID="com.github.targetcrafter.kdecaldav"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$SCRIPT_DIR/$PLUGIN_ID}"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "kpackagetool6 not found. This widget requires KDE Plasma 6." >&2
    exit 1
fi

if [ ! -e "$TARGET" ]; then
    echo "$TARGET not found." >&2
    exit 1
fi

if kpackagetool6 --type Plasma/Applet --show "$PLUGIN_ID" >/dev/null 2>&1; then
    echo "Upgrading existing installation..."
    kpackagetool6 --type Plasma/Applet --upgrade "$TARGET"
else
    echo "Installing..."
    kpackagetool6 --type Plasma/Applet --install "$TARGET"
fi

echo
echo "Done. Add it via: right-click desktop or panel -> Add Widgets... -> search 'CalDAV Agenda'."
echo "If it doesn't show up right away, restart Plasma: plasmashell --replace &"
