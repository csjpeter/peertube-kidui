#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# Tests manage.sh test-setup and test: a real browser against a throwaway static server.

set -eu

cd "$(dirname "$0")/.."
status=0

./manage.sh test-setup || { echo "FAIL: test-setup" >&2; exit 1; }
echo "ok: test-setup"

# Serve this checkout under /kidui, as nginx does, on a free loopback port.
site="build/e2e-site-$$"
mkdir -p "$site"
ln -s "$PWD" "$site/kidui"
port=$((20000 + $$ % 20000))
python3 -I -m http.server --bind 127.0.0.1 --directory "$site" "$port" >"build/e2e-server-$$.log" 2>&1 &
srv=$!
cleanup() {
	kill "$srv" 2>/dev/null || :
	rm -f "$site/kidui" "build/e2e-server-$$.log"
	rmdir "$site"
}
trap cleanup EXIT
i=0
until curl -fsS -o /dev/null "http://127.0.0.1:$port/kidui/"; do
	i=$((i + 1))
	if [ "$i" -gt 50 ]; then echo "FAIL: static server did not start" >&2; exit 1; fi
	sleep 0.1
done

if KIDUI_BASE_URL="http://127.0.0.1:$port/kidui" ./manage.sh test; then
	echo "ok: manage.sh test passes against a served page"
else
	echo "FAIL: manage.sh test failed against a served page" >&2
	status=1
fi

# A base URL nobody listens on must fail, not pass.
if KIDUI_BASE_URL="http://127.0.0.1:1/kidui" ./manage.sh test; then
	echo "FAIL: manage.sh test passed with no instance" >&2
	status=1
else
	echo "ok: manage.sh test fails when the instance is unreachable"
fi

exit "$status"
