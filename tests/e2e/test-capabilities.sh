#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# E2E tests of the existing capabilities against a seeded PeerTube (manage.sh peertube-seed).

set -eu

base="${KIDUI_BASE_URL:?KIDUI_BASE_URL is required}"
status=0

# The embed paths in the order the page lists them (the suggested view).
api="$(printf '%s' "$base" | sed 's|/kidui$||')"
embed1="$(curl -fsS "$api/api/v1/videos?sort=-views&count=100" | jq -r '.data[0].embedPath')"
embed2="$(curl -fsS "$api/api/v1/videos?sort=-views&count=100" | jq -r '.data[1].embedPath')"

# check NAME OPERATION...: runs browser-drive from a fresh page load of the app.
check() {
	name="$1"
	shift
	if browser-drive --timeout 20000 --url "$base/" "$@"; then
		echo "ok: $name"
	else
		echo "FAIL: $name" >&2
		status=1
	fi
}

check "the suggested videos are listed on start" \
	--wait '#content-list .video-item img' --expect-text '#top-bar .current-index=1/2'

check "the channel list shows a card with a thumbnail per channel" \
	--click '#btn_channels_top' \
	--expect-text '#page-title h1=Csatornák' \
	--wait '#content-list .video-item img[src*="/lazy-static/thumbnails/"]'

check "a channel card opens the channel's videos" \
	--click '#btn_channels_top' --expect-text '#page-title h1=Csatornák' \
	--wait '#content-list .video-item img[src*="/lazy-static/thumbnails/"]' \
	--click '#content-list .video-item' \
	--expect-text '#page-title h1=Cartoons' \
	--wait '#content-list .video-item img'

check "a video starts the embedded player and shows its index" \
	--wait '#content-list .video-item' --click '#content-list .video-item' \
	--wait '#embed-player[src*="/videos/embed/"]' \
	--expect-text '#top-bar .current-index=1/2'

check "playing a video hides the list and loads that video's embed" \
	--wait '#content-list .video-item' --click '#content-list .video-item' \
	--wait "#embed-player[src^=\"$embed1\"]" \
	--wait '#content-list[style*="display: none"]'

check "next and previous move the index and reload the embed" \
	--wait '#content-list .video-item' --click '#content-list .video-item' \
	--wait "#embed-player[src^=\"$embed1\"]" \
	--click '#btn_next_top' --expect-text '#top-bar .current-index=2/2' \
	--wait "#embed-player[src^=\"$embed2\"]" \
	--click '#btn_prev_top' --expect-text '#top-bar .current-index=1/2' \
	--wait "#embed-player[src^=\"$embed1\"]"

check "the repeat button toggles its look" \
	--click '#btn_repeat' --wait '#btn_repeat[style*="208, 221, 208"]' \
	--click '#btn_repeat' --wait '#btn_repeat[style*="240, 240, 240"]'

exit "$status"
