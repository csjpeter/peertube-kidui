#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# Tests the manage.sh fixtures verb and the approval guard of peertube-up.

set -eu

cd "$(dirname "$0")/.."
status=0

rm -f build/fixtures/video1.mp4 build/fixtures/video2.mp4 build/fixtures/video1.jpg build/fixtures/video2.jpg
if ./manage.sh fixtures; then
	for f in video1.mp4 video2.mp4 video1.jpg video2.jpg; do
		if [ -s "build/fixtures/$f" ]; then
			echo "ok: $f exists and is not empty"
		else
			echo "FAIL: build/fixtures/$f missing or empty" >&2
			status=1
		fi
	done
else
	echo "FAIL: manage.sh fixtures failed" >&2
	status=1
fi

# Without the approval variable the verb must refuse before touching podman.
if env -u KIDUI_DIGESTS_APPROVED ./manage.sh peertube-up; then
	echo "FAIL: peertube-up ran without the digest approval" >&2
	status=1
else
	echo "ok: peertube-up refuses without the digest approval"
fi

exit "$status"
