# ParkTrack 1.4.0

This release makes it easier to compare nearby parking options, inspect them on the map, and preview a route before starting a trip.

## What's new

- Added a compact, scrollable parking results panel ranked in the order returned by the service.
- Synchronized result selection with parking markers on Android and the web.
- Added a detailed parking view with a return path that preserves the result list and scroll position.
- Added quick “Go” and “Open in Yandex Maps” actions.
- Improved route preview so the complete route fits around the map controls and remains visible while the map is moved or zoomed.
- Replaced the destination circle with a precise pin marker.

## Fixes and improvements

- Added localized loading, empty, error, action, and parking-data labels in Russian and English.
- Improved result formatting, touch targets, small-screen behavior, and light/dark theme support.
- Added tests for search state, marker emphasis, formatting, external map links, route camera bounds, and destination markers.
