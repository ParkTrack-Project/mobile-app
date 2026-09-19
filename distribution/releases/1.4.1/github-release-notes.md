# ParkTrack 1.4.1

ParkTrack 1.4.1 fixes deep-link navigation and Android App Links association
across Android and Web/PWA.

## Fixes and improvements

### Android

- Fixed `parktrack://` and verified `https://m.parktrack.live` links so every
  supported URL opens its requested map, parking, route, destination, search,
  profile, or authentication section.
- Preserved protected link destinations while the stored session is checked
  and through sign-in, including links received while the app is already open.
- Kept the router instance stable across authentication changes and hardened
  internal redirects against unsupported external URLs.
- Centered the map on coordinates opened through destination links, including
  links received during application startup.
- Updated parking availability when a past or future time is selected and no
  longer substitutes the current count when temporal data is unavailable.
- Removed the Share action from the route preview card.
- Greatly reduced Android map work during live location, marker animation, and
  direction updates, eliminating redundant platform-view rebuilds and bitmap
  decoding.

### Web/PWA

- Fixed direct `m.parktrack.live` paths so their requested application section
  survives session loading and authentication redirects.
- Published `/.well-known/assetlinks.json` in the GitHub Pages artifact so
  Android can verify the `m.parktrack.live` association.
- Documented every supported deep link, parameter, compatibility form, and
  local verification command.
- Centered destination links after the Web map finishes loading.
- Updated map markers and cards with availability for the selected time and
  show a neutral unavailable state instead of the current count when needed.
- Removed the Share action from the route preview card.
