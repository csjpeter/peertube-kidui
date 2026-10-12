#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# Builds and runs the C E2E test of auto-advance and repeat mode against the seeded PeerTube.

set -eu

base="${KIDUI_BASE_URL:?KIDUI_BASE_URL is required}"
api="$(printf '%s' "$base" | sed 's|/kidui$||')"
list="$(curl -fsS "$api/api/v1/videos?sort=-views&count=100")"
KIDUI_EMBED1="$(printf '%s' "$list" | jq -r '.data[0].embedPath')"
KIDUI_EMBED2="$(printf '%s' "$list" | jq -r '.data[1].embedPath')"
export KIDUI_EMBED1 KIDUI_EMBED2

mkdir -p build/tmp
cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -o build/tmp/autoadvance tests/e2e/autoadvance.c \
	$(pkg-config --cflags --libs libbrowsertest)
BT_PROFILE_PARENT="$PWD/build/tmp" build/tmp/autoadvance
