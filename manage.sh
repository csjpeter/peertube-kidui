#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-11
# Project management script: check, fixtures, test-setup, test, coverage and the local PeerTube instance.

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
	sh tests/test-manage-fixtures.sh
	sh tests/test-manage-e2e.sh
	sh tests/test-coverage-report.sh
}

# Pinned by digest; the owner approves these on the ticket KIDUI-9 before any pull.
PEERTUBE_IMAGE="docker.io/chocobozzz/peertube@sha256:011b0ec43d921bd60a3aa01fc7995e42cf15275925f16bee6f17a6c896ca5060"
POSTGRES_IMAGE="docker.io/library/postgres@sha256:3645570cccdfa447589da9f57dd740faa29b30938e861289a5574b6ca6b03826"
REDIS_IMAGE="docker.io/library/redis@sha256:4fa24486b8bcca8eec45ee0eb166edc674795e53a2b53d1a9ef263eecebaac85"
PT_NET="kidui-test"
PT_DATA="build/peertube"
PT_PORT="9000"

# Two tiny videos with a thumbnail each, made locally by ffmpeg; nothing is fetched.
make_fixtures() {
	command -v ffmpeg >/dev/null || { echo "fixtures: ffmpeg is not installed" >&2; return 1; }
	out="build/fixtures"
	mkdir -p "$out"
	i=1
	for pattern in testsrc2 smptebars; do
		ffmpeg -loglevel error -y -f lavfi -i "${pattern}=size=320x180:rate=15:duration=6" \
			-f lavfi -i "sine=frequency=$((300 * i)):duration=6" \
			-c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/video$i.mp4" || return 1
		ffmpeg -loglevel error -y -i "$out/video$i.mp4" -frames:v 1 "$out/video$i.jpg" || return 1
		i=$((i + 1))
	done
	echo "fixtures: wrote $out/video1.mp4 video2.mp4 and their .jpg thumbnails"
}

# Starts PeerTube, PostgreSQL and Redis rootless under podman, on localhost only.
# Pulls images, so it runs only when the owner's digest approval is stated explicitly.
peertube_up() {
	if [ "${KIDUI_DIGESTS_APPROVED:-}" != "KIDUI-9" ]; then
		echo "peertube-up: the image digests need the owner's approval (KIDUI-9); set KIDUI_DIGESTS_APPROVED=KIDUI-9 once given" >&2
		return 1
	fi
	command -v podman >/dev/null || { echo "peertube-up: podman is not installed" >&2; return 1; }
	mkdir -p "$PT_DATA/db" "$PT_DATA/data" "$PT_DATA/redis"
	podman network exists "$PT_NET" || podman network create "$PT_NET"
	podman run -d --replace --name kidui-db --network "$PT_NET" \
		-e POSTGRES_USER=peertube -e POSTGRES_PASSWORD=peertube -e POSTGRES_DB=peertube \
		-v "$PWD/$PT_DATA/db:/var/lib/postgresql/data:Z" "$POSTGRES_IMAGE"
	podman run -d --replace --name kidui-redis --network "$PT_NET" \
		-v "$PWD/$PT_DATA/redis:/data:Z" "$REDIS_IMAGE"
	podman run -d --replace --name kidui-peertube --network "$PT_NET" \
		-p "127.0.0.1:$PT_PORT:9000" \
		-e PEERTUBE_DB_HOSTNAME=kidui-db -e PEERTUBE_DB_USERNAME=peertube \
		-e PEERTUBE_DB_PASSWORD=peertube -e PEERTUBE_REDIS_HOSTNAME=kidui-redis \
		-e PEERTUBE_WEBSERVER_HOSTNAME=localhost -e PEERTUBE_WEBSERVER_PORT="$PT_PORT" \
		-e PEERTUBE_WEBSERVER_HTTPS=false -e PEERTUBE_SECRET=0000000000000000000000000000000000000000000000000000000000000000 \
		-e PT_INITIAL_ROOT_PASSWORD=kidui-test-password -e PEERTUBE_ADMIN_EMAIL=admin@example.org \
		-v "$PWD/$PT_DATA/data:/data:Z" "$PEERTUBE_IMAGE"
}

# Seeds the local instance through its API: a second channel, one video in each of the
# two channels (the second with a name longer than the page shows and a description) and a
# public playlist of both. Steps already done are skipped, so it can run again.
peertube_seed() {
	command -v jq >/dev/null || { echo "peertube-seed: jq is not installed" >&2; return 1; }
	[ -s build/fixtures/video1.mp4 ] || make_fixtures || return 1
	base="http://localhost:$PT_PORT"
	client="$(curl -fsS "$base/api/v1/oauth-clients/local")" || return 1
	token="$(curl -fsS \
		-d "client_id=$(printf '%s' "$client" | jq -r .client_id)" \
		-d "client_secret=$(printf '%s' "$client" | jq -r .client_secret)" \
		-d grant_type=password -d response_type=code \
		--data-urlencode username=root --data-urlencode password=kidui-test-password \
		"$base/api/v1/users/token" | jq -r .access_token)" || return 1
	auth="Authorization: Bearer $token"
	code="$(curl -sS -o /dev/null -w '%{http_code}' "$base/api/v1/video-channels/cartoons")" || return 1
	if [ "$code" = "404" ]; then
		curl -fsS -H "$auth" -H 'Content-Type: application/json' \
			-d '{"name":"cartoons","displayName":"Cartoons"}' \
			"$base/api/v1/video-channels" >/dev/null || return 1
	fi
	i=1
	for channel in root_channel cartoons; do
		have="$(curl -fsS "$base/api/v1/video-channels/$channel/videos" | jq -r .total)" || return 1
		if [ "$have" = "0" ]; then
			cid="$(curl -fsS "$base/api/v1/video-channels/$channel" | jq -r .id)" || return 1
			name="Test video $i"
			if [ "$i" = "2" ]; then
				name="Test video 2 with a title much longer than the page lists"
			fi
			curl -fsS -H "$auth" \
				-F channelId="$cid" -F name="$name" -F privacy=1 \
				-F description="Description of test video $i" \
				-F videofile=@"build/fixtures/video$i.mp4" \
				-F thumbnailfile=@"build/fixtures/video$i.jpg" \
				-F previewfile=@"build/fixtures/video$i.jpg" \
				"$base/api/v1/videos/upload" >/dev/null || return 1
		fi
		i=$((i + 1))
	done
	lists="$(curl -fsS "$base/api/v1/video-playlists" | jq -r .total)" || return 1
	if [ "$lists" = "0" ]; then
		cid="$(curl -fsS "$base/api/v1/video-channels/root_channel" | jq -r .id)" || return 1
		pid="$(curl -fsS -H "$auth" -F displayName="Test playlist" -F privacy=1 \
			-F videoChannelId="$cid" "$base/api/v1/video-playlists" | jq -r .videoPlaylist.id)" || return 1
		for vid in $(curl -fsS "$base/api/v1/videos?sort=createdAt&count=100" | jq -r '.data[].id'); do
			curl -fsS -H "$auth" -H 'Content-Type: application/json' -d "{\"videoId\":$vid}" \
				"$base/api/v1/video-playlists/$pid/videos" >/dev/null || return 1
		done
	fi
	echo "peertube-seed: root_channel and cartoons hold one video each, plus a playlist of both"
}

peertube_down() {
	command -v podman >/dev/null || { echo "peertube-down: podman is not installed" >&2; return 1; }
	for c in kidui-peertube kidui-redis kidui-db; do
		podman container exists "$c" && podman rm -f "$c"
	done
	podman network exists "$PT_NET" && podman network rm "$PT_NET"
	return 0
}


# Without KIDUI_BASE_URL, test starts tests/support/kidui-proxy.py in front of the
# local PeerTube (peertube-up) and tests through it.
E2E_PROXY_PORT="8089"
E2E_BASE_URL="${KIDUI_BASE_URL:-http://127.0.0.1:$E2E_PROXY_PORT/kidui}"

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

# Runs every tests/e2e/test-*.sh against the instance at KIDUI_BASE_URL.
run_e2e() {
	test_setup || return 1
	if [ -z "${KIDUI_BASE_URL:-}" ]; then
		if ! curl -fsS -o /dev/null "http://localhost:$PT_PORT/api/v1/config"; then
			echo "test: no PeerTube on port $PT_PORT; run ./manage.sh peertube-up and peertube-seed, or set KIDUI_BASE_URL" >&2
			return 1
		fi
		python3 -I tests/support/kidui-proxy.py "$E2E_PROXY_PORT" "$PT_PORT" 2>build/tmp/proxy.log &
		proxy_pid=$!
		trap 'kill "$proxy_pid"' EXIT
		i=0
		until curl -fsS -o /dev/null "$E2E_BASE_URL/"; do
			i=$((i + 1))
			if [ "$i" -gt 50 ]; then echo "test: proxy did not start; see build/tmp/proxy.log" >&2; return 1; fi
			sleep 0.1
		done
	fi
	if ! curl -fsS -o /dev/null "$E2E_BASE_URL/"; then
		echo "test: $E2E_BASE_URL is not reachable; start the instance or set KIDUI_BASE_URL" >&2
		return 1
	fi
	failed=0
	found=0
	for t in ${KIDUI_E2E_TESTS:-tests/e2e/test-*.sh}; do
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

# Runs the E2E suite with the JavaScript coverage collected and requires every line
# of the <script> blocks of index.html to have run (tests/support/coverage-report.sh).
run_coverage() {
	rm -rf build/coverage
	mkdir -p build/coverage
	KIDUI_COVERAGE_DIR="$PWD/build/coverage"
	export KIDUI_COVERAGE_DIR
	run_e2e || return 1
	sh tests/support/coverage-report.sh index.html build/coverage
}

case "${1:-}" in
fixtures)
	make_fixtures
	;;
peertube-up)
	peertube_up
	;;
peertube-down)
	peertube_down
	;;
peertube-seed)
	peertube_seed
	;;
test-setup)
	test_setup
	;;
test)
	run_e2e
	;;
coverage)
	run_coverage
	;;
check)
	check_private_domain
	check_js_tests
	;;
*)
	echo "usage: $0 check|fixtures|peertube-up|peertube-down|peertube-seed|test-setup|test|coverage" >&2
	exit 2
	;;
esac
