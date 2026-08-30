#!/usr/bin/env bash
# Builds a .plasmoid archive that can be installed via kpackagetool6, or
# through Plasma's "Get New Widgets... -> Install Widget From Local File..."
# dialog, without needing a checkout or the command line at all.
set -euo pipefail

PLUGIN_ID="com.github.targetcrafter.kdecaldav"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/$PLUGIN_ID"
OUT_FILE="$SCRIPT_DIR/$PLUGIN_ID.plasmoid"

if [ ! -f "$SRC_DIR/metadata.json" ]; then
    echo "Expected $SRC_DIR/metadata.json - run this from the repository root." >&2
    exit 1
fi

rm -f "$OUT_FILE"
# metadata.json and contents/ must sit at the archive root (not inside a
# wrapping folder) for kpackagetool6/Plasma to recognize it.
(cd "$SRC_DIR" && zip -rq "$OUT_FILE" metadata.json contents)

echo "Built $OUT_FILE"
