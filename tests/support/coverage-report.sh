#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# Merges the JavaScript coverage reports of the E2E runs (browser-drive --coverage,
# bt_coverage_take) and reports the line coverage of the <script> blocks of index.html.
#
# usage: coverage-report.sh HTML COVERAGE_DIR
# Writes COVERAGE_DIR/report.json and report.html, prints a summary and the uncovered
# lines; exits 1 below 100%.

set -eu

html="${1:?usage: coverage-report.sh HTML COVERAGE_DIR}"
dir="${2:?usage: coverage-report.sh HTML COVERAGE_DIR}"

set -- "$dir"/*.json
case "$1" in
*/'*.json')
	echo "coverage: no coverage files in $dir" >&2
	exit 1
	;;
esac
# A previous report is not an input.
inputs=""
for f in "$@"; do
	case "$f" in
	*/report.json) ;;
	*) inputs="$inputs $f" ;;
	esac
done
if [ -z "$inputs" ]; then
	echo "coverage: no coverage files in $dir" >&2
	exit 1
fi

# The body lines of every inline <script> block (1-based, inclusive ranges).
ranges="$(awk '/<script>/ { s = NR + 1 } /<\/script>/ { if (s) { print s, NR - 1; s = 0 } }' "$html" |
	jq -Rn '[inputs | split(" ") | map(tonumber)]')"

# The highest count of every line of the page's own scripts over all runs; the
# scripts of the embedded player and the handlers of attributes are not the page's blocks.
# shellcheck disable=SC2086
jq -s --argjson ranges "$ranges" '
	[ .[].scripts[] | select(.url | test("/kidui/(index\\.html)?$")) | .lines[] ]
	| group_by(.[0])
	| map({ line: .[0][0], count: (map(.[1]) | max) })
	| map(select(. as $l | $ranges | any(.[0] <= $l.line and $l.line <= .[1])))
	| { lines: ., total: length, covered: (map(select(.count > 0)) | length) }
	| .percent = (if .total == 0 then 0 else (.covered * 10000 / .total | floor) / 100 end)
	| .uncovered = (.lines | map(select(.count == 0) | .line))
' $inputs >"$dir/report.json"

total="$(jq .total "$dir/report.json")"
covered="$(jq .covered "$dir/report.json")"
percent="$(jq .percent "$dir/report.json")"

# An annotated copy of the source for reading.
jq -r '.lines[] | "\(.line) \(.count)"' "$dir/report.json" |
	awk -v title="index.html line coverage ${percent}%" '
		NR == FNR { c[$1] = $2; next }
		FNR == 1 {
			print "<!doctype html><meta charset=\"utf-8\"><title>" title "</title>"
			print "<style>body{font:13px monospace}.u{background:#f9c0c0}.c{background:#c8f0c8}</style>"
			print "<h1>" title "</h1><pre>"
		}
		{
			line = $0
			gsub(/&/, "\\&amp;", line); gsub(/</, "\\&lt;", line); gsub(/>/, "\\&gt;", line)
			cls = (FNR in c) ? ((c[FNR] > 0) ? "c" : "u") : "n"
			printf "<span class=\"%s\">%5d  %s</span>\n", cls, FNR, line
		}
		END { print "</pre>" }
	' - "$html" >"$dir/report.html"

echo "coverage: index.html script blocks: $covered of $total lines covered ($percent%)"
echo "coverage: report: $dir/report.json, $dir/report.html"
if [ "$covered" -ne "$total" ]; then
	echo "coverage: FAILED: uncovered lines:" >&2
	jq -r '.uncovered[]' "$dir/report.json" | while read -r n; do
		printf '  %5d  %s\n' "$n" "$(sed -n "${n}p" "$html")" >&2
	done
	exit 1
fi
