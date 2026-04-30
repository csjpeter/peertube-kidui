# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A single-file (`index.html`) kid-friendly PeerTube web frontend designed for private family use on a local network. No build system, no package manager, no dependencies — pure HTML/CSS/JavaScript served as a static file by nginx.

## Deployment

The app is served by nginx at the `/kidui` path (symlinked to `/var/www/peertube/kidui`). The nginx config at `etc/nginx/sites-available/peertube` must include the `/kidui` location block with the appropriate CSP headers (see README.md for the exact snippet).

After editing `index.html`, no build step is needed — nginx serves the file directly.

## Architecture

Everything lives in `index.html`. The JavaScript is split into four `<script>` blocks, each initialised on `DOMContentLoaded`:

- **`videoPlayer()`** — core logic. Fetches PeerTube REST API (`/api/v1/`) for channels, playlists, and videos. Maintains `currentVideos[]` and `currentIndex`. Embeds videos via a sandboxed `<iframe id="embed-player">`. Auto-advance and repeat-current-video are handled by listening to the `ended` event on `iframe.contentDocument.querySelector('video')`.
- **`wakeLocker()`** — requests `navigator.wakeLock` to prevent the screen from sleeping during playback (skipped on Firefox/Safari where it misbehaves).
- **`toggleFullScreen()`** — cross-browser fullscreen toggle exposed as a global.
- **`updateTexts()`** — i18n: reads `navigator.language`, picks `hu` or `en` from a hardcoded `translations` object, and updates button text by element id.

### Layout

- **`#top-bar`** — shown in portrait and on desktop; hidden on touch landscape.
- **`#right-bar`** — shown only on touch landscape (replaces the top bar).
- Both bars contain the same buttons; both share the `.current-index` span for `currentIndex+1 / total` display.

### API endpoints used

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/video-channels?count=100` | list channels |
| `GET /api/v1/video-channels/{name}/videos?count=100` | channel videos |
| `GET /api/v1/video-playlists?count=100` | list playlists |
| `GET /api/v1/video-playlists/{id}/videos` | playlist videos |
| `GET /api/v1/videos?sort=-views&count=100` | suggested videos (default view) |

All URLs are constructed dynamically from `window.location.protocol` and `window.location.hostname`, so no hardcoded server address appears in the app.

### Code style

Functions use vim fold markers (`//{{{` … `//}}}`) for collapsing in editors that support them. Keep this convention when adding new functions.

## Configuration files (examples, not the live server)

- `var/www/peertube/config/production.yaml` — example PeerTube config (family instance: Hungarian, no federation, HLS only, P2P disabled).
- `etc/nginx/sites-available/peertube` — example nginx config for the PeerTube + kidui setup.
