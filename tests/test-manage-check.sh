#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-11
# Tests that manage.sh check passes on a clean tree and fails on the private domain.

set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

probe="tests/probe-private-domain.txt"
# Assembled from parts so that this test does not name the domain in one piece.
printf 'user@%s.%s\n' "csaszar" "email" > "$probe"
git add "$probe"

status=0
if ./manage.sh check; then
	echo "FAIL: check passed although a tracked file names the private domain" >&2
	status=1
else
	echo "ok: check fails on the private domain"
fi

git rm -q -f --cached "$probe"
rm -f "$probe"

if ./manage.sh check; then
	echo "ok: check passes on a clean tree"
else
	echo "FAIL: check fails on a clean tree" >&2
	status=1
fi

exit "$status"
