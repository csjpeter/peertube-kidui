/* SPDX-License-Identifier: GPL-3.0-only */
/* Copyright (c) 2026 Peter Csaszar (Császár Péter) */
/* Created: 2026-10-12 */
/* Helpers shared by the C E2E tests: reporting, waiting and JavaScript coverage collection. */
#ifndef KIDUI_E2E_H
#define KIDUI_E2E_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <browsertest.h>

static int failures;
static int coverage_runs;

static void report(const char *name, int ok, const char *detail)
{
    if (ok) {
        printf("ok: %s\n", name);
    } else {
        fprintf(stderr, "FAIL: %s: %s\n", name, detail ? detail : "");
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

/* The text of the first match, never NULL; the caller frees it. */
static char *page_text(bt_browser *b, const char *selector)
{
    char *t = bt_text(b, selector);
    return t ? t : strdup("");
}

/* With KIDUI_COVERAGE_DIR set, counts the JavaScript coverage of the browser's run. */
static void coverage_begin(bt_browser *b)
{
    if (getenv("KIDUI_COVERAGE_DIR") && bt_coverage_start(b) != 0) {
        fprintf(stderr, "  coverage start: %s\n", bt_error(b));
        failures++;
    }
}

/* Writes what ran since coverage_begin() to KIDUI_COVERAGE_DIR/PREFIX-N.json. */
static void coverage_end(bt_browser *b, const char *prefix)
{
    const char *dir = getenv("KIDUI_COVERAGE_DIR");
    if (!dir)
        return;
    char *json = bt_coverage_take(b);
    char path[512];
    snprintf(path, sizeof path, "%s/%s-%d.json", dir, prefix, ++coverage_runs);
    FILE *f = json ? fopen(path, "w") : NULL;
    if (!f || fputs(json, f) == EOF) {
        fprintf(stderr, "  coverage: cannot write %s: %s\n", path, json ? "write failed" : bt_error(b));
        failures++;
    }
    if (f)
        fclose(f);
    free(json);
}

#endif
