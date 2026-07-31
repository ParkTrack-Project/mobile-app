# ParkTrack 1.4.0

ParkTrack 1.4.0 introduces a new way to compare parking options on the map,
with richer search results, clearer parking and route details, more dependable
location tracking, and smoother map interactions across Android and Web/PWA.

## What's new

### Android

- Added a redesigned, scrollable search results panel with up to 10 parking
  options synchronized with their markers on the map.
- Search results now show the estimated arrival time, walking time to the
  destination, current and forecast free spaces, price, parking number, and
  address. Open any result as a full parking card and move directly between
  neighboring results without returning to the list.
- Parking cards now show when current or historical availability was updated.
  For future selections they show both the forecast target and creation times,
  warn when the nearest forecast differs by at least 30 minutes, and provide a
  shortcut to open that forecast.
- Added route previews before navigation, with the complete route, trip
  details, and quick actions for in-app navigation and Yandex Maps.
- Added Share actions for parking cards and routes, with descriptive text and
  direct links that can be opened in ParkTrack.
- Redesigned parking and cluster markers. The selected parking area stays
  prominent while surrounding areas are dimmed, and the map remains fully
  interactive so you can pan, zoom, and inspect nearby options with a card
  open.
- Refreshed the Where am I, compass, `+`, and `-` controls, and added an
  explicit follow mode that keeps the location centered and rotates the map
  with the current heading.
- Added a new direction-aware location marker and network-first positioning on
  Android. ParkTrack now prefers Wi-Fi/cellular location, falls back to GPS
  when needed, and keeps the last known position visible during temporary
  signal loss.
- Added complete verified `m.parktrack.live` App Links and `parktrack://`
  links for the map, parking cards, destinations, search, profile, and
  authentication screens.

### Web/PWA

- Added the redesigned parking results panel, full parking cards, and direct
  navigation between neighboring results to the Yandex Maps web experience.
- Added detailed current and forecast availability, arrival and walking times,
  prices, addresses, destination markers, route previews, and in-app
  navigation controls.
- Parking cards now include data update times and complete forecast timing,
  with a mismatch warning and a shortcut to the nearest available forecast.
- Added Share actions for parking and routes using the browser share sheet,
  with a fallback for browsers that do not support it.
- Redesigned parking markers, clustering, and selection so the active parking
  area remains clear while the map stays interactive.
- Refreshed the location, compass, zoom, and follow controls; added smoother
  marker movement and two-finger map rotation.
- Added direct website paths for the map, parking cards, destinations, search,
  profile, and authentication sections.

## Fixes and improvements

### Android

- Restored reliable opening of parking cards from taps on map markers and
  parking zones.
- Fixed route previews so the complete route is framed in the available map
  area above the card, with the start near the bottom and the destination near
  the top.
- Coordinated parking-card, marker, and camera animations for smoother
  transitions without repeated refocusing or visible jumps.
- Improved handling of unavailable or interrupted location sources: the last
  position remains visible, stale data is shown appropriately, and tracking
  retries automatically.
- Fixed rapid and held `+`/`-` input so every zoom step is applied; zooming in
  follow mode no longer bounces back or disables following.
- Repositioned map controls above parking, destination, route, and navigation
  panels, with adaptive behavior on small screens and improved control and
  location-marker contrast.
- Improved parking cards with hour-and-minute walking times, highlighted paid
  prices, color-coded availability forecasts, and timezone-independent arrival
  estimates.
- Improved route-building progress and navigation distance formatting, and
  kept the selected destination marker fully visible.
- Refined parking loading and clustering, added automatic availability
  refreshes, parallelized parking-marker bitmap generation, and reduced
  redundant zone requests, redraws, and camera updates. Also removed unused
  routing and localization code.
- Improved Android release compatibility with edge-to-edge layouts, 16 KB page
  sizes, optimized resource shrinking, and current Google Play requirements.
- Expanded regression coverage for parking search, map controls, route
  previews, location sources and markers, navigation, sharing, deep links, and
  clustering.

### Web/PWA

- Fixed route previews on narrow screens and for very long routes so the full
  path and both endpoints remain visible above the route card.
- Fixed route and parking sharing so it no longer depends on an unavailable
  native Flutter plugin channel in the browser.
- Coordinated bottom-card and camera animations, removed repeated route and
  parking refits, and made location-marker movement smoother.
- Kept zoom, compass, and Where am I controls available around parking,
  destination, route, and navigation panels whenever the screen has room.
- Improved parking cards with hour-and-minute walking times, highlighted paid
  prices, color-coded availability forecasts, and timezone-independent arrival
  estimates.
- Improved map theme synchronization, compass behavior, marker selection,
  route overlays, parking visibility around viewport edges, and small-screen
  layouts.
- Reduced unnecessary work by updating moving location markers without
  serializing and redrawing every parking zone.
- Improved route-provider fallback behavior, deep-link recovery, and
  preservation of protected destinations through authentication.
