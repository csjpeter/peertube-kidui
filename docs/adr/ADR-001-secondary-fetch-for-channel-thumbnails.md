# ADR-001: Secondary Per-Item Fetch for Channel Video Thumbnails

Status: Accepted
Date: 2026-04-30

## Context

The PeerTube `GET /api/v1/video-channels` endpoint returns channel metadata
(avatar, name, etc.) but does not include thumbnails of the channel's video
content. Displaying a video thumbnail on each channel card requires a
separate API call per channel.

## Decision

On channel list load, after retrieving the channel list, fire one
`GET /api/v1/video-channels/{name}/videos?count=1&sort=-publishedAt`
request per channel concurrently via `Promise.all`. Use the first returned
video's `thumbnailPath` (prefixed with `BASE_URL`) as the channel card image.
Each per-channel fetch is guarded with `.catch(() => null)` so a single
failure never breaks the whole channel list.

Channel list items are rendered with `class="video-item"` (instead of the
text-only `class="list-item"`) to reuse the existing card-with-image layout.

## Rationale

- No new external dependencies — standard `fetch` + `Promise.all`.
- N+1 requests on channel list load is acceptable: the target is a small
  family PeerTube instance on a LAN with ≤ ~20 channels.
- Reusing `.video-item` CSS avoids duplicating image-card styles.

## Consequences

- Future list views that need child-resource data should follow the same
  `Promise.all` + `.catch(() => null)` pattern.
- If the channel count grows significantly (> 50), consider adding a
  server-side endpoint or caching to reduce request count.
