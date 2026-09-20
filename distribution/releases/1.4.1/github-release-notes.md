# ParkTrack 1.4.1

ParkTrack 1.4.1 improves deep-link navigation, selected-time parking data, and
map performance across the Android and Web/PWA applications.

## What's new

### Android

- Added complete `parktrack://` and verified `https://m.parktrack.live` link
  coverage for the map, parking, saved routes, destinations, search, profile,
  profile editing, sign-in, registration, and password reset.
- Added selected-time availability to parking zones and cards, with neutral
  unavailable states when temporal data is missing.

### Web/PWA

- Added the same path-based deep-link coverage as Android, including direct
  links to parking, routes, destinations, search, profile, and authentication.
- Documented all supported URL forms, parameters, compatibility aliases, and
  Android verification commands.

## Fixes and improvements

### Android

- Preserved protected link destinations while the stored session is checked
  and through sign-in, including links received while the app is already open.
- Kept the router instance stable across authentication changes and rejected
  unsupported external redirect destinations.
- Centered the map on coordinates opened through destination links.
- Requested and displayed the correct current, historical, or forecast
  availability for the active time selection.
- Removed the Share action from route previews.
- Calculated the route-preview arrival time from the same driving duration
  shown in the card, preventing stale server estimates from disagreeing with
  the selected route.
- Replaced neutral outlines on the Time and Now map controls with the same
  subtle shadow as the other controls, while retaining the green selected-time
  outline.
- Greatly reduced Android map work during live location, marker animation, and
  direction updates, eliminating redundant platform-view rebuilds and bitmap
  decoding.

### Web/PWA

- Preserved requested paths through session loading and authentication.
- Fixed GitHub Pages packaging so `/.well-known/assetlinks.json` remains in the
  final deployment artifact and Android can verify `m.parktrack.live`.
- Associated both the Google Play and GitHub release signing certificates so
  verified links work with either Android distribution.
- Kept a direct-path SPA fallback for browsers while packaging the association
  document as a real root file with an HTTP 200 response.
- Centered destination links after the Web map finishes loading.
- Updated map markers and cards with availability for the selected time and a
  neutral unavailable state when temporal data is missing.
- Removed the Share action from route previews.
- Calculated route-preview arrival time from the displayed driving duration.
- Softened the Time and Now controls while retaining the selected-time outline.
