#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# Builds and runs the C E2E test of the paths real data does not reach by itself.

set -eu

base="${KIDUI_BASE_URL:?KIDUI_BASE_URL is required}"

mkdir -p build/tmp
cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -o build/tmp/edge-cases tests/e2e/edge-cases.c \
	$(pkg-config --cflags --libs libbrowsertest)
BT_PROFILE_PARENT="$PWD/build/tmp" build/tmp/edge-cases
