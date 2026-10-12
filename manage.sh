#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-11
# Project management script: currently the check verb only.

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
}

case "${1:-}" in
check)
	check_private_domain
	check_js_tests
	;;
*)
	echo "usage: $0 check" >&2
	exit 2
	;;
esac
