/* SPDX-License-Identifier: GPL-3.0-only */
/* Copyright (c) 2026 Peter Csaszar (Császár Péter) */
/* Created: 2026-10-12 */
/* E2E test of auto-advance and repeat mode: seeks the embedded video to its end in a real browser. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <browsertest.h>

static int failures;

static void report(const char *name, int ok, const char *detail)
{
    if (ok) {
        printf("ok: %s\n", name);
    } else {
        fprintf(stderr, "FAIL: %s: %s\n", name, detail);
        failures++;
    }
}

/* Waits for the selector; on failure prints the library's reason. */
static int wait_for(bt_browser *b, const char *selector, int ms)
{
    int rc = bt_wait_for(b, selector, BT_WAIT_PRESENT, ms);
    if (rc != 0) {
        fprintf(stderr, "  wait %s: %s\n", selector, bt_error(b));
    }
    return rc == 0;
}

/* Waits (in the page) until the embedded <video> has metadata, seeks it to just before
 * its end, counts its ended events in window.__ended and plays it muted. */
static const char *SEEK_NEAR_END =
    "(async () => {"
    "  const doc = () => document.getElementById('embed-player').contentDocument;"
    "  let v = null;"
    "  for (let i = 0; i < 300; i++) {"
    "    v = doc() && doc().querySelector('video');"
    "    if (v && v.readyState >= 1 && isFinite(v.duration) && v.duration > 1) break;"
    "    await new Promise(r => setTimeout(r, 100));"
    "  }"
    "  if (!v || !(v.duration > 1)) return 'no-video';"
    "  window.__ended = 0;"
    "  document.getElementById('embed-player').contentWindow.__kiduiOld = true;"
    "  v.addEventListener('ended', () => { window.__ended++; });"
    "  v.muted = true;"
    "  v.currentTime = v.duration - 0.5;"
    "  try { await v.play(); } catch (e) { return 'play-failed: ' + e; }"
    "  return 'seeked';"
    "})()";

static char *page_text(bt_browser *b, const char *selector)
{
    char *t = bt_text(b, selector);
    return t ? t : strdup("");
}

static int start_first_video(bt_browser *b, const char *base, const char *embed1)
{
    char sel[512];
    char url[512];
    snprintf(url, sizeof url, "%s/", base);
    if (bt_navigate(b, url) != 0)
        return 0;
    if (!wait_for(b, "#content-list .video-item", 20000))
        return 0;
    if (bt_click(b, "#content-list .video-item") != 0)
        return 0;
    snprintf(sel, sizeof sel, "#embed-player[src^=\"%s\"]", embed1);
    return wait_for(b, sel, 20000);
}

int main(void)
{
    const char *base = getenv("KIDUI_BASE_URL");
    const char *embed1 = getenv("KIDUI_EMBED1");
    const char *embed2 = getenv("KIDUI_EMBED2");
    char err[256] = "";
    char sel[512];

    if (!base || !embed1 || !embed2) {
        fprintf(stderr, "autoadvance: KIDUI_BASE_URL, KIDUI_EMBED1 and KIDUI_EMBED2 are required\n");
        return 2;
    }

    /* Headless Chromium otherwise refuses to start the player without a user gesture. */
    static const char *const extra[] = { "--autoplay-policy=no-user-gesture-required", NULL };
    bt_options opts;
    memset(&opts, 0, sizeof opts);
    opts.timeout_ms = 30000;
    opts.extra_args = extra;

    /* Auto-advance: at the end of video 1 the page starts video 2 and the index becomes 2/2. */
    bt_browser *b = bt_open(&opts, err, sizeof err);
    if (!b) {
        fprintf(stderr, "autoadvance: cannot start the browser: %s\n", err);
        return 3;
    }
    if (!start_first_video(b, base, embed1)) {
        report("auto-advance: first video starts", 0, bt_error(b));
    } else {
        char *r = bt_eval(b, SEEK_NEAR_END);
        int seeked = r && strstr(r, "seeked") != NULL;
        report("auto-advance: video seeked near its end", seeked, r ? r : bt_error(b));
        free(r);
        snprintf(sel, sizeof sel, "#embed-player[src^=\"%s\"]", embed2);
        int moved = seeked && wait_for(b, sel, 30000);
        report("auto-advance: the next video's embed is loaded", moved, "embed did not change");
        char *idx = page_text(b, "#top-bar .current-index");
        report("auto-advance: the index is 2/2", strcmp(idx, "2/2") == 0, idx);
        free(idx);
    }
    bt_close(b);

    /* Repeat mode: at the end of video 1 the same video stays, the index stays 1/2. */
    b = bt_open(&opts, err, sizeof err);
    if (!b) {
        fprintf(stderr, "autoadvance: cannot start the browser: %s\n", err);
        return 3;
    }
    if (!start_first_video(b, base, embed1) || bt_click(b, "#btn_repeat") != 0) {
        report("repeat: first video starts and repeat is on", 0, bt_error(b));
    } else {
        char *r = bt_eval(b, SEEK_NEAR_END);
        int seeked = r && strstr(r, "seeked") != NULL;
        report("repeat: video seeked near its end", seeked, r ? r : bt_error(b));
        free(r);
        char *ended = bt_eval(b,
            "(async () => { for (let i = 0; i < 150; i++) {"
            " if (window.__ended >= 1) return 'ended';"
            " await new Promise(r => setTimeout(r, 200)); } return 'not-ended'; })()");
        report("repeat: the video reached its end", ended && strstr(ended, "ended") && !strstr(ended, "not-ended"),
               ended ? ended : bt_error(b));
        free(ended);
        /* The page must have loaded the same video again: a new embed document. */
        char *reload = bt_eval(b,
            "(async () => { for (let i = 0; i < 150; i++) {"
            " const f = document.getElementById('embed-player');"
            " if (f.contentWindow && !f.contentWindow.__kiduiOld && f.contentDocument.querySelector('video'))"
            "   return 'reloaded ' + f.getAttribute('src');"
            " await new Promise(r => setTimeout(r, 200)); } return 'not-reloaded'; })()");
        int same = reload && strncmp(reload, "reloaded ", 9) == 0 && strstr(reload, embed1) != NULL;
        report("repeat: the same video is loaded again", same, reload ? reload : bt_error(b));
        free(reload);
        char *idx = page_text(b, "#top-bar .current-index");
        report("repeat: the index is still 1/2", strcmp(idx, "1/2") == 0, idx);
        free(idx);
    }
    bt_close(b);

    return failures ? 1 : 0;
}
