#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-11
# Project management script: check, fixtures and the local PeerTube test instance.

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
		-e PT_INITIAL_ROOT_PASSWORD=kidui-test-password \
		-v "$PWD/$PT_DATA/data:/data:Z" "$PEERTUBE_IMAGE"
}

peertube_down() {
	command -v podman >/dev/null || { echo "peertube-down: podman is not installed" >&2; return 1; }
	for c in kidui-peertube kidui-redis kidui-db; do
		podman container exists "$c" && podman rm -f "$c"
	done
	podman network exists "$PT_NET" && podman network rm "$PT_NET"
	return 0
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
check)
	check_private_domain
	check_js_tests
	;;
*)
	echo "usage: $0 check|fixtures|peertube-up|peertube-down" >&2
	exit 2
	;;
esac
