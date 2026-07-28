# ParkTrack 1.4.0

ParkTrack 1.4.0 makes parking selection and route planning faster, clearer, and
more reliable across Android and the web app.

## What's new

### Android

- Added a compact, scrollable parking results panel synchronized with markers
  on the map.
- Added detailed parking cards, route previews, and quick Route and Yandex Maps
  actions.
- Added complete verified `m.parktrack.live` App Links and `parktrack://`
  custom links for the map, parking cards, destinations, search, profile, and
  authentication screens.
- Added a Yandex Maps-style location marker that follows device heading and
  refreshed the compass and map controls.

### Web/PWA

- Added synchronized parking results and parking cards to the Yandex Maps web
  experience.
- Added destination markers, route previews, and in-app navigation controls.
- Added direct path links for map, parking, destination, search, profile, and
  authentication sections.

## Fixes and improvements

### Android

- Restored reliable parking-card opening from map taps.
- Improved route-building progress feedback and navigation distance formatting.
- Improved zoom-button hold behavior, map-control placement on small screens,
  and location-marker contrast.
- Parallelized parking marker bitmap generation and removed unused routing and
  localization code.
- Added focused coverage for map controls, parking cards, route previews,
  location markers, navigation statistics, deep links, and routing states.

### Web/PWA

- Stopped serializing and redrawing all parking zones for every GPS position
  update; moving markers now use a lightweight update path.
- Improved map theme synchronization, compass behavior, marker selection,
  routing overlays, and small-screen control placement.
- Improved deep-link fallback behavior and preserved protected destinations
  through authentication.
