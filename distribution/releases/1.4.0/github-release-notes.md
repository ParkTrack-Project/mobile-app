# ParkTrack 1.4.0

ParkTrack 1.4.0 makes parking selection and route planning faster, clearer, and
more reliable across Android and the web app.

## What's new

### Android

- Added a compact, scrollable parking results panel synchronized with markers
  on the map.
- Added detailed parking cards, route previews, and quick Route and Yandex Maps
  actions.
- Parking cards now slide smoothly from the bottom of the map, with coordinated
  camera movement to the selected parking area.
- Added complete verified `m.parktrack.live` App Links and `parktrack://`
  custom links for the map, parking cards, destinations, search, profile, and
  authentication screens.
- Added a Yandex Maps-style location marker that follows device heading and
  refreshed the compass and map controls.

### Web/PWA

- Added synchronized parking results and parking cards to the Yandex Maps web
  experience.
- Added destination markers, route previews, and in-app navigation controls.
- Parking-card opening and route-preview camera movement now use smoother,
  coordinated animations.
- Added direct path links for map, parking, destination, search, profile, and
  authentication sections.

## Fixes and improvements

### Android

- Restored reliable parking-card opening from map taps.
- Fixed route previews so the full route is visible above the route card, with
  the destination near the top and the start near the bottom of the map.
- Fixed `+` and `-` zoom buttons in follow mode so single taps change zoom
  without bouncing back or leaving follow mode.
- Repositioned the location and compass controls above destination cards and
  the navigation bottom panel.
- Improved route-building progress feedback and navigation distance formatting.
- Improved parking search cards with hour-and-minute walking times, highlighted
  paid prices, and color-coded availability forecasts.
- Improved zoom-button hold behavior, map-control placement on small screens,
  and location-marker contrast.
- Fixed parking arrival estimates so API-provided local times remain consistent
  across device time zones.
- Reduced redundant zone fetches, optimized parking-cluster overlap merging,
  and removed repeated route/parking camera refits after panel measurement.
- Parallelized parking marker bitmap generation and removed unused routing and
  localization code.
- Added focused coverage for map controls, parking cards, route previews,
  location markers, navigation statistics, deep links, and routing states.

### Web/PWA

- Fixed route and parking sharing so the browser share sheet no longer fails
  when a native Flutter plugin channel is unavailable.
- Stopped serializing and redrawing all parking zones for every GPS position
  update; moving markers now use a lightweight update path.
- Fixed route-preview framing so routes fit in the visible map area above the
  route card.
- Repositioned location and compass controls around destination cards and
  navigation panels.
- Improved map theme synchronization, compass behavior, marker selection,
  routing overlays, and small-screen control placement.
- Improved parking search cards with hour-and-minute walking times, highlighted
  paid prices, and color-coded availability forecasts.
- Fixed parking arrival estimates so API-provided local times remain consistent
  across browser time zones.
- Improved deep-link fallback behavior and preserved protected destinations
  through authentication.
