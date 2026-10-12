#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# Tests tests/support/coverage-report.sh on synthetic coverage files.

set -eu

cd "$(dirname "$0")/.."
status=0
work="build/tmp/coverage-report-test-$$"
mkdir -p "$work/none" "$work/gap" "$work/merged" "$work/full"
cleanup() {
	( cd build/tmp && rm -rf "coverage-report-test-$$" )
}
trap cleanup EXIT

# Lines 3 to 5 are the body of the only script block; line 7 is a handler attribute.
cat >"$work/page.html" <<'HTML'
<html>
<script>
function a() {
  return 1;
}
</script>
<button onclick="a()">x</button>
</html>
HTML

# A report with the script block (startLine 1, 0-based, so its lines are 3..5) and the
# handler attribute: lines is [[line, count], ...].
report() {
	printf '{"scripts":[{"url":"http://h/kidui/","startLine":1,"startColumn":8,"lines":[[3,%s],[4,%s],[5,%s]]},' "$1" "$2" "$3"
	printf '{"url":"http://h/kidui/","startLine":6,"startColumn":20,"lines":[[7,%s]]},' "$4"
	printf '{"url":"http://h/videos/embed/x","startLine":0,"startColumn":0,"lines":[[3,0]]}]}\n'
}

expect() {
	name="$1"
	want="$2"
	dir="$3"
	out="$work/out.txt"
	set +e
	sh tests/support/coverage-report.sh "$work/page.html" "$dir" >"$out" 2>&1
	rc=$?
	set -e
	if [ "$rc" -eq "$want" ]; then
		echo "ok: $name"
	else
		echo "FAIL: $name: exit $rc, wanted $want" >&2
		cat "$out" >&2
		status=1
	fi
}

has() {
	if grep -q -- "$2" "$work/out.txt"; then
		echo "ok: $1"
	else
		echo "FAIL: $1: '$2' not in the output" >&2
		cat "$work/out.txt" >&2
		status=1
	fi
}

report 1 1 1 0 >"$work/full/a.json"
expect "full coverage passes; the embed's and the attribute handler's scripts do not count" 0 "$work/full"
has "the summary names 100%" "(100%)"
test -s "$work/full/report.html" && echo "ok: the HTML report is written" || { echo "FAIL: no HTML report" >&2; status=1; }

report 1 0 1 1 >"$work/gap/a.json"
expect "a gap fails" 1 "$work/gap"
has "the gap names its line and text" "4    return 1;"

report 1 0 1 1 >"$work/merged/a.json"
report 0 3 0 1 >"$work/merged/b.json"
expect "coverage of several runs is merged" 0 "$work/merged"

expect "no coverage files fails" 1 "$work/none"

exit "$status"
