# ParkTrack 1.3.0

This release brings the ParkTrack experience to the web and improves reliability across the Android and web apps.

## What's new

- Added full Yandex Maps support to the web app, including parking details, place search, route building, and navigation.
- Added Android App Links for opening `m.parktrack.live` URLs directly in the app.
- Added language selection to the sign-in, registration, and password reset screens.
- Added a guide for installing the web app on an iPhone.

## Fixes and improvements

- Preserved cached parking data during recoverable network failures and added clearer, localized error messages with retry actions.
- Synchronized the web map theme and language with the app and disabled unintended interactions with base-map POIs.
- Improved web map rendering, camera updates, route display, zone selection, and zero-availability markers.
- Improved map and navigation stability while reducing unnecessary redraws, storage operations, and background work.
- Optimized Android release builds with code minification and unused-resource removal.
- Improved the Android release workflow.
