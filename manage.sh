#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-11
# Project management script: check, test-setup and test.

set -eu

cd "$(dirname "$0")"

# The private domain is built from two parts so that this script does not
# contain it in one piece and fails its own check.
PRIVATE_DOMAIN_NAME="csaszar"
PRIVATE_DOMAIN_TLD="email"

check_private_domain() {
	pattern="${PRIVATE_DOMAIN_NAME}\\.${PRIVATE_DOMAIN_TLD}"
	if git grep -nIiE "$pattern"; then
		echo "check: FAILED: a tracked file names the private domain" >&2
		return 1
	fi
	echo "check: private domain: ok"
}

check_js_tests() {
	for t in tests/test-*.js; do
		node "$t" || return 1
	done
	sh tests/test-manage-e2e.sh
}

E2E_BASE_URL="${KIDUI_BASE_URL:-http://localhost:9000/kidui}"

# The E2E tools are the workspace's own libbrowsertest (browser-drive) and a system
# Chromium: nothing is fetched from a registry.
test_setup() {
	missing=0
	if command -v browser-drive >/dev/null; then
		browser-drive --version
	else
		echo "test-setup: browser-drive not found; install libbrowsertest from the workspace repository" >&2
		missing=1
	fi
	browser="${BT_BROWSER:-}"
	if [ -z "$browser" ]; then
		browser="$(command -v chromium || command -v chromium-browser || true)"
	fi
	if [ -n "$browser" ] && [ -x "$browser" ]; then
		echo "test-setup: browser: $browser"
	else
		echo "test-setup: no Chromium found (set BT_BROWSER or install chromium)" >&2
		missing=1
	fi
	mkdir -p build/tmp
	return "$missing"
}

# Runs every tests/e2e/test-*.sh against the live instance at KIDUI_BASE_URL.
run_e2e() {
	test_setup || return 1
	if ! curl -fsS -o /dev/null "$E2E_BASE_URL/"; then
		echo "test: $E2E_BASE_URL is not reachable; start the instance or set KIDUI_BASE_URL" >&2
		return 1
	fi
	failed=0
	found=0
	for t in tests/e2e/test-*.sh; do
		[ -e "$t" ] || continue
		found=1
		echo "== $t"
		KIDUI_BASE_URL="$E2E_BASE_URL" BT_PROFILE_PARENT="$PWD/build/tmp" sh "$t" || failed=1
	done
	if [ "$found" -eq 0 ]; then
		echo "test: no tests in tests/e2e" >&2
		return 1
	fi
	return "$failed"
}

case "${1:-}" in
test-setup)
	test_setup
	;;
test)
	run_e2e
	;;
check)
	check_private_domain
	check_js_tests
	;;
*)
	echo "usage: $0 check|test-setup|test" >&2
	exit 2
	;;
esac
