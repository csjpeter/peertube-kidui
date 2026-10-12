#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# E2E smoke test: the page loads in a real browser and its bars and player are in the DOM.

set -eu

base="${KIDUI_BASE_URL:?KIDUI_BASE_URL is required}"
status=0

n=0
check() {
	name="$1"
	shift
	n=$((n + 1))
	if browser-drive --timeout 15000 ${KIDUI_COVERAGE_DIR:+--coverage "$KIDUI_COVERAGE_DIR/structure-$n.json"} --url "$base/" "$@"; then
		echo "ok: $name"
	else
		echo "FAIL: $name" >&2
		status=1
	fi
}

check "top bar is present" --wait '#top-bar'
check "content list is present" --wait '#content-list'
check "embedded player is present" --wait '#embed-player'
check "channels button is present" --wait '#btn_channels_top'

exit "$status"
