# Publishing OmAnnotate to the Omarchy plugin marketplace

The marketplace is [plugins.omarchy.org](https://plugins.omarchy.org/). Listings
are requested with a GitHub issue on
[omacom/omarchy-plugin-marketplace](https://github.com/omacom/omarchy-plugin-marketplace)
(see its `SUBMISSION.md`). It lists plugins; it does not review their security.

## What the marketplace uses

| Item | Where it comes from |
|---|---|
| Name, version, author, description | `manifest.json` |
| Logo | Not used by the marketplace. `icon.png` is for the README, the GitHub social preview and anywhere a square image is wanted. |
| Card and detail image | `preview.png` in the repository root (2400×1200). The marketplace makes a 720 px card image and a 1600 px detail image itself; cards crop to about 2:1. |
| Badge (the square tile shown without a preview) | Drawn by the marketplace from two letters and an accent color. Letters come from the name split at spaces, `-` and `_`, so "OmAnnotate" alone gives **O**; ask for **OA** in the maintainer notes. Accent colors: lime, amber, coral, cyan, violet, rose (the default for `omannotate` is violet; amber is closest to Omarchy's orange). |
| Category, tags | The submission issue |

## Before submitting

- [x] Public GitHub repository whose root is this folder: https://github.com/Z0H0wizard/omannotate
- [x] `manifest.json` has an `author` (shown on the card): Legendary Solutions.
- [x] A `LICENSE` file in the root (MIT, © 2026 Legendary Solutions). OmAnnotate has no external dependencies (README → License).
- [x] `omarchy plugin validate` accepts a fresh clone of the public repository
      (checked 2026-09-23).
- [x] The README's install command shows the real repository URL.
- [ ] A clean install from the public URL works:
      `omarchy plugin add https://github.com/Z0H0wizard/omannotate --enable`, then Super+Ctrl+drag draws and
      OmAnnotate under Apps opens the settings. (On 2026-09-23 the whole cycle
      passed from a local `file://` clone: install, launcher, drawing,
      settings, update, disable/enable and removal. The public URL is not
      tested yet.)
- [ ] README has install and removal instructions (it does: Install, Remove).

## Submission issue

Open <https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml>,
or file an issue titled `[Plugin]: OmAnnotate` with exactly these six headings:

```markdown
### Repository URL

https://github.com/Z0H0wizard/omannotate

### Category

Productivity

### Tags

hyprland, quickshell

### Suggest a missing tag

annotation

### Maintainer notes

OmAnnotate lets you hold Super+Ctrl and drag to draw fading lines on any screen,
for screen shares and recordings. It is a service + panel plugin: the service
registers its own Super+Ctrl+left-click bind at runtime with `hyprctl eval`
(again after each Hyprland config reload); it does not edit Hyprland
configuration. So that the settings are reachable from the Omarchy menu, it
links ~/.local/share/applications/omannotate.desktop and a hicolor icon to
files inside the plugin folder, so it appears under Apps with its logo (a
settings switch turns this off). Those links are removed when the plugin is
disabled or removed, and only links pointing into an omannotate plugin folder
are ever removed. No configuration file is edited; settings live in the
plugin's own shell.json entry. Please use the initials OA and the amber accent
for the badge.

### Submission checklist

- [x] The repository is public and its README explains installation and removal.
- [x] The plugin license and external dependencies are documented.
- [x] I own or have permission to publish the plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval lists the plugin and is not a security review.
```

## Updating a listing

Bump `version` in `manifest.json` and `codeVersion` in `Service.qml` together
(the service compares them to tell users a shell restart is needed after
`omarchy plugin update`), and `VERSION` in
`hypr/omannotate.lua` whenever that file changes, so running copies take over
the new code. Push,
then use the marketplace's verification form to publish the newer commit. The
listed snapshot stays until the new commit passes its checks.
