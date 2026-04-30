# Browse Channel List with Video Thumbnails

- User opens the app → channel list is displayed; each channel card shows
  a thumbnail image taken from the channel's latest video
- Channel has no videos → card shows the channel's own avatar instead;
  if no avatar either, a generic placeholder image is shown
- Thumbnail finishes loading → image appears in the card without layout shift
- Thumbnail fails to load → fallback to channel avatar or placeholder silently
- User taps a channel card → channel video list opens (existing behaviour unchanged)
