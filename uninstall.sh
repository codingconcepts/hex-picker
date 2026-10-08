#!/bin/bash
set -uo pipefail

APP_NAME="Hex Picker"
BUNDLE_NAME="${APP_NAME}.app"
BUNDLE_ID="com.hexpicker.app"
INSTALL_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLED="${INSTALL_DIR}/${BUNDLE_NAME}"

# --keep-installed: sweep stale copies but leave the /Applications install, its
# Dock tile and its saved colours alone. Used by `make install`, so installing
# never leaves a second copy behind for Spotlight to offer.
KEEP_INSTALLED=0
[ "${1:-}" = "--keep-installed" ] && KEEP_INSTALLED=1

if [ "${KEEP_INSTALLED}" -eq 1 ]; then
    echo "Pruning stale ${APP_NAME} copies..."
else
    echo "Uninstalling ${APP_NAME}..."
    # Stop the running app.
    pkill -f "hex_picker" 2>/dev/null && sleep 0.5
fi

# 1. Remove every copy of the bundle we know how to create.
BUNDLES=(
    "${HOME}/Applications/${BUNDLE_NAME}"
    "${HOME}/.Trash/${BUNDLE_NAME}"
    "${REPO_DIR}/build/dmg_staging/${BUNDLE_NAME}"
    "${REPO_DIR}/build/${BUNDLE_NAME}"
)
[ "${KEEP_INSTALLED}" -eq 0 ] && BUNDLES+=("${INSTALLED}")

for bundle in "${BUNDLES[@]}"; do
    [ -e "${bundle}" ] || continue
    echo "  removing ${bundle}"
    # Unregister before deleting: lsregister needs the bundle to still be there.
    "${LSREGISTER}" -u "${bundle}" 2>/dev/null
    rm -rf "${bundle}" 2>/dev/null || echo "    could not delete (locked or protected) — remove by hand"
done
rm -rf "${REPO_DIR}/build/dmg_staging" 2>/dev/null

# 2. Drop stale Launch Services rows left by bundles deleted without unregistering
#    (these are what keep the app in Spotlight and "Open With" after a manual delete).
ls_paths() {
    "${LSREGISTER}" -dump 2>/dev/null \
        | awk -v name="${BUNDLE_NAME}" '$1 == "path:" {
              sub(/^path:[ \t]*/, ""); sub(/ \(0x[0-9a-f]+\)$/, "");
              if (index($0, name)) print
          }' \
        | sort -u
}

while read -r stale; do
    [ -n "${stale}" ] || continue
    [ "${KEEP_INSTALLED}" -eq 1 ] && [ "${stale}" = "${INSTALLED}" ] && continue
    echo "  unregistering ${stale}"
    "${LSREGISTER}" -u "${stale}" 2>/dev/null
done < <(ls_paths)

if [ "${KEEP_INSTALLED}" -eq 0 ]; then
    # 3. Remove the Dock tile, which survives deletion of the bundle it points at.
    if command -v dockutil >/dev/null 2>&1; then
        dockutil --remove "${APP_NAME}" --no-restart >/dev/null 2>&1
    else
        /usr/bin/python3 - "${BUNDLE_ID}" "${APP_NAME}" <<'PY'
import plistlib, subprocess, sys

bundle_id, app_name = sys.argv[1], sys.argv[2]
exported = subprocess.run(["defaults", "export", "com.apple.dock", "-"],
                          capture_output=True).stdout
dock = plistlib.loads(exported)

def ours(tile):
    data = tile.get("tile-data", {})
    url = data.get("file-data", {}).get("_CFURLString", "")
    return (data.get("bundle-identifier") == bundle_id
            or data.get("file-label") == app_name
            or app_name.replace(" ", "%20") + ".app" in url)

changed = False
for key in ("persistent-apps", "recent-apps"):
    tiles = dock.get(key, [])
    kept = [t for t in tiles if not ours(t)]
    if len(kept) != len(tiles):
        dock[key] = kept
        changed = True

if changed:
    subprocess.run(["defaults", "import", "com.apple.dock", "-"],
                   input=plistlib.dumps(dock))
PY
    fi
    killall Dock 2>/dev/null

    # 4. Remove user data: saved colours, window state, caches.
    defaults delete "${BUNDLE_ID}" 2>/dev/null
    rm -f  "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
    rm -rf "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"
    rm -rf "${HOME}/Library/Caches/${BUNDLE_ID}"
    rm -rf "${HOME}/Library/Containers/${BUNDLE_ID}"
    rm -rf "${HOME}/Library/HTTPStorages/${BUNDLE_ID}"
fi

# 5. Report anything still referencing the app.
remaining=0
while read -r path; do
    [ -n "${path}" ] || continue
    [ "${KEEP_INSTALLED}" -eq 1 ] && [ "${path}" = "${INSTALLED}" ] && continue
    echo "  still registered: ${path}"
    remaining=$((remaining + 1))
done < <(ls_paths)

if [ "${remaining}" -gt 0 ]; then
    echo "Launch Services still lists ${remaining} copy(ies). Log out and back in, or run:"
    echo "  ${LSREGISTER} -kill -r -domain local -domain system -domain user"
elif [ "${KEEP_INSTALLED}" -eq 1 ]; then
    echo "Clean: ${INSTALLED} is the only registered copy."
else
    echo "Done. No references left."
fi
