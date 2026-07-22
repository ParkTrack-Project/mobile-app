# Release 1.3.0

## Changes

### Android
- Added support for m.parktrack.live App Links.
- Added language switcher to all auth screens.
- Improved error handling and offline data preservation.
- Fixed location permission and network error reporting.

### Web & PWA
- Synchronized map theme and locale with the app.
- Disabled accidental interactions with base map POIs.
- Added iOS PWA installation guide.
- Formatted and optimized Yandex Maps JS bridge.

### Core
- Centralized `AppFailure` logic for better reliability.
- Implemented stale-while-revalidate pattern for parking data.
- Added non-intrusive error banners with retry capability.
