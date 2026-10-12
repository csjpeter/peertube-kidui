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
| `GET /api/v1/video-channels/{name}/videos?count=1&sort=-publishedAt` | latest video of a channel: its thumbnail is the channel card image (ADR-001) |
| `GET /api/v1/video-playlists?count=100` | list playlists |
| `GET /api/v1/video-playlists/{id}/videos` | playlist videos |
| `GET /api/v1/videos?sort=-views&count=100` | suggested videos (default view) |

All URLs are constructed dynamically from `window.location.origin`, so no hardcoded server address appears in the app.

### Code style

Functions use vim fold markers (`//{{{` … `//}}}`) for collapsing in editors that support them. Keep this convention when adding new functions.

## Commands

```bash
./manage.sh check          # private-domain check, node unit tests, self-tests of the verbs
./manage.sh fixtures       # two test videos + thumbnails by ffmpeg, into build/fixtures
./manage.sh peertube-up    # rootless podman: PeerTube, PostgreSQL, Redis by digest, 127.0.0.1:9000
                           # (needs KIDUI_DIGESTS_APPROVED=KIDUI-9: the images are pulled)
./manage.sh peertube-seed  # one video in root_channel and in cartoons, and a playlist of both
./manage.sh test-setup     # verifies browser-drive (libbrowsertest) and a system Chromium
./manage.sh test           # tests/e2e/test-*.sh; through tests/support/kidui-proxy.py
                           # unless KIDUI_BASE_URL names an instance
./manage.sh coverage       # runs the E2E suite with JavaScript coverage (browser-drive --coverage,
                           # bt_coverage_*); build/coverage/report.{json,html}; fails below 100%
                           # of the lines of the <script> blocks of index.html
./manage.sh peertube-down  # removes the containers and the network (data stays in build/peertube)
```

E2E tests drive a real headless Chromium through `browser-drive` from the workspace's own
libbrowsertest; Playwright and npm are not used. The page builds its URLs from
`window.location.origin`, so it works on any port.

## Configuration files (examples, not the live server)

- `var/www/peertube/config/production.yaml` — example PeerTube config (family instance: Hungarian, no federation, HLS only, P2P disabled).
- `etc/nginx/sites-available/peertube` — example nginx config for the PeerTube + kidui setup.
