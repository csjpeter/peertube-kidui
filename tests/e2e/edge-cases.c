/* SPDX-License-Identifier: GPL-3.0-only */
/* Copyright (c) 2026 Peter Csaszar (Császár Péter) */
/* Created: 2026-10-12 */
/* E2E tests of the paths real PeerTube data does not reach by itself: playlists, entries the
 * API never sends, failing thumbnail requests, unreadable embeds, the wake lock, the
 * fullscreen fallbacks and the key log.  The real page runs in a real browser; where the
 * server's answer must differ, the page's fetch is wrapped by the test. */
#include "kidui-e2e.h"

/* Steps of a scenario: wait for a selector, click one, compare an element's text, or run
 * JavaScript in the page (an async function body) and require its answer to contain WANT. */
enum op { WAIT, CLICK, TEXT, EVAL, END };

struct step {
    enum op op;
    const char *label;
    const char *arg;
    const char *want;
};

struct scenario {
    const char *name;
    struct step steps[16];
};

/* The helpers put before every EVAL body; the error counter exists from the first EVAL. */
#define PRELUDE \
    "const sleep = ms => new Promise(r => setTimeout(r, ms));" \
    "const until = async (f, n = 100) => { for (let i = 0; i < n; i++) {" \
    "  const v = f(); if (v) return v; await sleep(100); } return null; };" \
    "if (window.__errs === undefined) { window.__errs = 0;" \
    "  window.addEventListener('error', () => { window.__errs++; }); }"

static const struct scenario SCENARIOS[] = {
    { "playlists", {
        { EVAL, "the playlist list shows each playlist with its thumbnail",
          "const orig = window.fetch;"
          "window.fetch = async (u, ...a) => { const r = await orig(u, ...a);"
          "  if (String(u).includes('/video-playlists?')) { const d = await r.json();"
          "    d.data.forEach(p => { p.thumbnail = location.origin + p.thumbnailPath; });"
          "    return new Response(JSON.stringify(d)); }"
          "  return r; };"
          "await loadPlaylists();"
          "const it = await until(() => document.querySelector('#content-list .list-item'));"
          "return 'title=' + (document.querySelector('#page-title h1')?.textContent === 'Lejátszási Listák')"
          "  + ';name=' + it.textContent"
          "  + ';thumb=' + !!it.querySelector('img[alt=\"Thumbnail for Test playlist\"]');",
          "title=true;name=Test playlist;thumb=true" },
        { CLICK, "a playlist opens", "#content-list .list-item", NULL },
        { WAIT, "the playlist's videos are listed", "#content-list .video-item", NULL },
        { TEXT, "the title is the playlist's", "#page-title h1", "Test playlist" },
        { TEXT, "the index counts the playlist's videos", "#top-bar .current-index", "1/2" },
        { CLICK, "the second video of the playlist starts", "#content-list .video-item:nth-child(2)", NULL },
        { WAIT, "its embed is loaded", "#embed-player[src*=\"/videos/embed/\"]", NULL },
        { TEXT, "the index is that of the playlist position", "#top-bar .current-index", "2/2" },
        { EVAL, "the video's description is shown",
          "return document.querySelector('#video-description p').textContent;",
          "Description of test video 2" },
        { END, NULL, NULL, NULL } } },

    { "suggested names", {
        { EVAL, "a long name is shortened to forty characters with an ellipsis",
          "const names = [...document.querySelectorAll('#content-list .video-item p')].map(p => p.textContent);"
          "const cut = names.filter(n => n.endsWith('...'));"
          "return 'cut=' + cut.length + ';len=' + (cut[0] || '').length;",
          "cut=1;len=40" },
        { END, NULL, NULL, NULL } } },

    { "channel thumbnails fall back", {
        { EVAL, "a missing thumbnail and a failing request end at the placeholder",
          "const orig = window.fetch;"
          "window.fetch = async (u, ...a) => { const s = String(u);"
          "  if (s.includes('sort=-publishedAt')) {"
          "    if (s.includes('/root_channel/'))"
          "      return new Response(JSON.stringify({ data: [{ thumbnailPath: '/missing-thumbnail.jpg' }] }));"
          "    return new Response('', { status: 500 }); }"
          "  return orig(u, ...a); };"
          "await loadChannels();"
          "const ok = await until(() => { const im = [...document.querySelectorAll('#content-list .video-item img')];"
          "  return im.length === 2 && im.every(i => i.src.startsWith('data:image/svg+xml')); });"
          "return 'placeholders=' + !!ok;",
          "placeholders=true" },
        { END, NULL, NULL, NULL } } },

    { "invalid video entries", {
        { EVAL, "a channel's videos without a name or a thumbnail are skipped",
          "window.__warn = 0; console.warn = () => { window.__warn++; };"
          "const orig = window.fetch;"
          "window.fetch = async (u, ...a) => { const r = await orig(u, ...a);"
          "  if (String(u).includes('/video-channels/cartoons/videos?count=100')) { const d = await r.json();"
          "    d.data.unshift({ name: 'no thumbnail' }, { thumbnailPath: '/x.jpg' });"
          "    return new Response(JSON.stringify(d)); }"
          "  return r; };"
          "await loadChannels();"
          "await until(() => document.querySelectorAll('#content-list .video-item').length === 2);"
          "return 'cards';",
          "cards" },
        { CLICK, "the Cartoons channel opens", "#content-list .video-item", NULL },
        { EVAL, "its title is the channel's",
          "await until(() => document.querySelector('#page-title h1')?.textContent === 'Cartoons');"
          "return 'title=' + document.querySelector('#page-title h1').textContent;",
          "title=Cartoons" },
        { EVAL, "only the valid video is listed and each broken entry warned",
          "await until(() => document.querySelectorAll('#content-list .video-item').length === 1);"
          "return 'items=' + document.querySelectorAll('#content-list .video-item').length + ';warn=' + window.__warn;",
          "items=1;warn=2" },
        { TEXT, "the index counts only the valid video", "#top-bar .current-index", "1/1" },
        { CLICK, "the valid video starts", "#content-list .video-item", NULL },
        { WAIT, "its embed is loaded", "#embed-player[src*=\"/videos/embed/\"]", NULL },
        { CLICK, "next stays on the only valid video", "#btn_next_top", NULL },
        { EVAL, "the embed is still a real video and the index is 1/1",
          "await sleep(500);"
          "return 'embed=' + document.getElementById('embed-player').getAttribute('src').includes('/videos/embed/')"
          "  + ';index=' + document.querySelector('#top-bar .current-index').textContent;",
          "embed=true;index=1/1" },
        { END, NULL, NULL, NULL } } },

    { "video without a description", {
        { EVAL, "a channel's videos come without descriptions",
          "const orig = window.fetch;"
          "window.fetch = async (u, ...a) => { const r = await orig(u, ...a);"
          "  if (String(u).includes('/video-channels/cartoons/videos?count=100')) { const d = await r.json();"
          "    d.data.forEach(v => { v.description = null; }); return new Response(JSON.stringify(d)); }"
          "  return r; };"
          "await loadChannels();"
          "await until(() => document.querySelectorAll('#content-list .video-item').length === 2);"
          "return 'cards';",
          "cards" },
        { CLICK, "the Cartoons channel opens", "#content-list .video-item", NULL },
        { EVAL, "its video is listed",
          "await until(() => document.querySelector('#page-title h1')?.textContent === 'Cartoons'"
          "  && document.querySelector('#content-list .video-item'));"
          "return 'listed';",
          "listed" },
        { CLICK, "the video starts", "#content-list .video-item", NULL },
        { WAIT, "its embed is loaded", "#embed-player[src*=\"/videos/embed/\"]", NULL },
        { EVAL, "no description is shown",
          "const d = document.getElementById('video-description');"
          "return 'h3=' + d.querySelectorAll('h3').length + ';text=[' + d.textContent + ']';",
          "h3=0;text=[]" },
        { END, NULL, NULL, NULL } } },

    { "a video that cannot start", {
        { EVAL, "the first playlist entry is a bare video, the second a wrapped one",
          "window.__err = 0; console.error = () => { window.__err++; };"
          "const orig = window.fetch;"
          "window.fetch = async (u, ...a) => { const r = await orig(u, ...a);"
          "  if (/\\/video-playlists\\/\\d+\\/videos/.test(String(u))) { const d = await r.json();"
          "    d.data[0] = d.data[0].video; return new Response(JSON.stringify(d)); }"
          "  return r; };"
          "await loadPlaylists();"
          "await until(() => document.querySelector('#content-list .list-item'));"
          "return 'ready';",
          "ready" },
        { CLICK, "the playlist opens", "#content-list .list-item", NULL },
        { WAIT, "its videos are listed", "#content-list .video-item", NULL },
        { CLICK, "the wrapped video is chosen", "#content-list .video-item:nth-child(2)", NULL },
        { EVAL, "the failure is logged once and not thrown",
          "await until(() => window.__err > 0); return 'errors=' + window.__err + ';uncaught=' + window.__errs;",
          "errors=1;uncaught=0" },
        { CLICK, "the page still works: channels", "#btn_channels_top", NULL },
        { EVAL, "the channel list is shown",
          "await until(() => document.querySelector('#page-title h1')?.textContent === 'Csatornák');"
          "return 'channels=' + (document.querySelector('#page-title h1')?.textContent === 'Csatornák');",
          "channels=true" },
        { END, NULL, NULL, NULL } } },

    { "embed documents", {
        { CLICK, "a video starts", "#content-list .video-item", NULL },
        { WAIT, "its embed is loaded", "#embed-player[src*=\"/videos/embed/\"]", NULL },
        { EVAL, "a load event with the video already present is harmless",
          "const f = document.getElementById('embed-player');"
          "const v = await until(() => f.contentDocument && f.contentDocument.querySelector('video'), 150);"
          "if (!v) return 'no-video';"
          "f.dispatchEvent(new Event('load'));"
          "return 'again;errors=' + window.__errs;",
          "again;errors=0" },
        { EVAL, "an embed from another origin cannot be read and is tolerated",
          "const f = document.getElementById('embed-player'); window.__loads = 0;"
          "f.addEventListener('load', () => { window.__loads++; });"
          "const other = location.protocol + '//' + (location.hostname === 'localhost' ? '127.0.0.1' : 'localhost')"
          "  + (location.port ? ':' + location.port : '') + '/';"
          "f.src = other;"
          "await until(() => window.__loads >= 1, 150);"
          "return 'unreadable=' + (f.contentDocument === null) + ';errors=' + window.__errs;",
          "unreadable=true;errors=0" },
        { END, NULL, NULL, NULL } } },

    { "key log", {
        { EVAL, "a key press is logged in the page",
          "createKeyPressLogDiv();"
          "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'MediaPlayPause' }));"
          "const p = document.querySelector('#key-press-log-container p');"
          "return 'log=' + (p && p.textContent);",
          "log=Key pressed: MediaPlayPause" },
        { END, NULL, NULL, NULL } } },

    { "wake lock", {
        { EVAL, "the lock is requested, its release is logged and the timer moves the pointer",
          "window.__logs = []; console.log = (...a) => { window.__logs.push(a.join(' ')); };"
          "let lock = null; navigator.wakeLock.request = async () => { lock = new EventTarget(); return lock; };"
          "let tick = null; let ms = 0; const si = window.setInterval;"
          "window.setInterval = (f, t) => { tick = f; ms = t; return 0; };"
          "let moves = 0; window.addEventListener('mousemove', () => { moves++; });"
          "wakeLocker(); window.setInterval = si;"
          "await until(() => lock); await new Promise(r => setTimeout(r, 50));"
          "lock.dispatchEvent(new Event('release')); tick();"
          "return 'logs=' + window.__logs.join(';') + ';ms=' + ms + ';moves=' + moves;",
          "logs=Screen Wake Lock is active;Screen Wake Lock was released;ms=50000;moves=1" },
        { END, NULL, NULL, NULL } } },

    { "fullscreen", {
        { EVAL, "the button handler is installed",
          "return 'errors=' + window.__errs;", "errors=0" },
        { CLICK, "the fullscreen button is clicked", "#btn_fullscreen_top", NULL },
        { EVAL, "clicking it raises no error",
          "await sleep(300); return 'errors=' + window.__errs;", "errors=0" },
        { EVAL, "each browser family's enter and exit call is used when it is the one present",
          "const de = document.documentElement; const out = [];"
          "const enter = (name, tag) => { de[name] = () => { window.__fs = tag; }; toggleFullScreen(); out.push(window.__fs); de[name] = undefined; };"
          "de.requestFullscreen = undefined;"
          "enter('mozRequestFullScreen', 'moz'); enter('webkitRequestFullscreen', 'webkit'); enter('msRequestFullscreen', 'ms');"
          "Object.defineProperty(document, 'fullscreenElement', { get: () => de, configurable: true });"
          "const leave = (name, tag) => { document[name] = () => { window.__fs = tag; }; toggleFullScreen(); out.push(window.__fs); document[name] = undefined; };"
          "document.exitFullscreen = undefined;"
          "leave('mozCancelFullScreen', 'moz-exit'); leave('webkitExitFullscreen', 'webkit-exit'); leave('msExitFullscreen', 'ms-exit');"
          "return out.join(',');",
          "moz,webkit,ms,moz-exit,webkit-exit,ms-exit" },
        { EVAL, "the standard calls are used when present",
          "const de = document.documentElement; const out = [];"
          "de.requestFullscreen = () => { window.__fs = 'request'; };"
          "Object.defineProperty(document, 'fullscreenElement', { get: () => null, configurable: true });"
          "toggleFullScreen(); out.push(window.__fs);"
          "Object.defineProperty(document, 'fullscreenElement', { get: () => de, configurable: true });"
          "document.exitFullscreen = () => { window.__fs = 'exit'; };"
          "toggleFullScreen(); out.push(window.__fs);"
          "return out.join(',');",
          "request,exit" },
        { END, NULL, NULL, NULL } } },
};

static int run_step(bt_browser *b, const char *scenario, const struct step *s)
{
    char name[256];
    snprintf(name, sizeof name, "%s: %s", scenario, s->label);
    switch (s->op) {
    case WAIT: {
        int ok = bt_wait_for(b, s->arg, BT_WAIT_PRESENT, 20000) == 0;
        report(name, ok, bt_error(b));
        return ok;
    }
    case CLICK: {
        int ok = bt_click(b, s->arg) == 0;
        report(name, ok, bt_error(b));
        return ok;
    }
    case TEXT: {
        char *t = page_text(b, s->arg);
        int ok = strcmp(t, s->want) == 0;
        report(name, ok, t);
        free(t);
        return ok;
    }
    case EVAL: {
        size_t n = strlen(PRELUDE) + strlen(s->arg) + 64;
        char *js = malloc(n);
        if (!js)
            return 0;
        snprintf(js, n, "(async () => { %s%s })()", PRELUDE, s->arg);
        char *r = bt_eval(b, js);
        free(js);
        int ok = r && strstr(r, s->want) != NULL;
        report(name, ok, r ? r : bt_error(b));
        free(r);
        return ok;
    }
    case END:
        break;
    }
    return 0;
}

int main(void)
{
    const char *base = getenv("KIDUI_BASE_URL");
    char err[256] = "";
    char url[512];

    if (!base) {
        fprintf(stderr, "edge-cases: KIDUI_BASE_URL is required\n");
        return 2;
    }
    snprintf(url, sizeof url, "%s/", base);

    bt_options opts;
    memset(&opts, 0, sizeof opts);
    opts.timeout_ms = 30000;

    for (size_t i = 0; i < sizeof SCENARIOS / sizeof SCENARIOS[0]; i++) {
        const struct scenario *sc = &SCENARIOS[i];
        bt_browser *b = bt_open(&opts, err, sizeof err);
        if (!b) {
            fprintf(stderr, "edge-cases: cannot start the browser: %s\n", err);
            return 3;
        }
        coverage_begin(b);
        if (bt_navigate(b, url) != 0 || !wait_for(b, "#content-list .video-item", 20000)) {
            report(sc->name, 0, "the page did not list its videos");
        } else {
            for (const struct step *s = sc->steps; s->op != END; s++) {
                if (!run_step(b, sc->name, s))
                    break;
            }
        }
        coverage_end(b, "edge-cases");
        bt_close(b);
    }
    return failures ? 1 : 0;
}
