.pragma library

// OmAnnotate's app launcher: links into the plugin folder made by
// bin/omannotate-launcher (see there).

function links(dataHome) {
  return [
    dataHome + "/applications/omannotate.desktop",
    dataHome + "/icons/hicolor/512x512/apps/omannotate.png"
  ]
}

// Run detached when the service stops. A restart or an update leaves the plugin
// installed and enabled, so the links stay. `omarchy plugin disable` and
// `omarchy plugin remove` stop the service and then take the plugin out of
// shell.json or delete its folder; after the delay the links are removed, so
// the app list drops the launcher (it rescans only when its folder changes).
// Enabling the plugin again recreates them. Only links that point into an
// omannotate plugin folder are removed; anything else at those paths stays.
function cleanupCommand(dataHome, delaySeconds) {
  var script = [
    'sleep "$1"; shift',
    'if [ -d "$HOME/.config/omarchy/plugins/omannotate" ] && jq -e \'any(.plugins[]?; .id == "omannotate")\' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then exit 0; fi',
    'for link; do case $(readlink -- "$link") in */plugins/omannotate/*) rm -f -- "$link" ;; esac; done',
    'exit 0'
  ].join("\n")
  return ["sh", "-c", script, "omannotate-cleanup", String(delaySeconds === undefined ? 3 : delaySeconds)]
    .concat(links(dataHome))
}
