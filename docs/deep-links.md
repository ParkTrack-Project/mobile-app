# ParkTrack deep links

ParkTrack supports verified Android App Links on `m.parktrack.live`, Web URLs,
and the `parktrack://` custom scheme. All forms resolve to the same application
sections on Android and Web. HTTPS is the preferred public format; the custom
scheme is a fallback for clients that cannot use Android App Links.

| Section | HTTPS App Link | Custom scheme |
| --- | --- | --- |
| Map | `https://m.parktrack.live/map` | `parktrack://map` |
| Parking card | `https://m.parktrack.live/parking/42` | `parktrack://parking/42` |
| Saved route | `https://m.parktrack.live/route/7` | `parktrack://route/7` |
| Destination | `https://m.parktrack.live/destination?lat=61.789114&lon=34.359757&name=Station` | `parktrack://destination?lat=61.789114&lon=34.359757&name=Station` |
| Search | `https://m.parktrack.live/search?q=station` | `parktrack://search?q=station` |
| Profile | `https://m.parktrack.live/profile` | `parktrack://profile` |
| Edit profile | `https://m.parktrack.live/profile/edit` | `parktrack://profile/edit` |
| Sign in | `https://m.parktrack.live/login` | `parktrack://login` |
| Registration | `https://m.parktrack.live/register` | `parktrack://register` |
| Password reset | `https://m.parktrack.live/password-reset` | `parktrack://password-reset` |

## Parameters

| Link | Parameters | Rules |
| --- | --- | --- |
| `/map` | `id` or `zoneId`, `q`, `lat`, `lon`, `name` | IDs must be positive integers. Coordinates must be a valid pair. |
| `/parking/:id` | `id` path segment | Opens the parking card for a positive parking-zone ID. |
| `/route/:id` | `id` path segment | Opens a saved route with a positive route ID. |
| `/destination` | `lat`, `lon`, optional `name` | Latitude: -90…90; longitude: -180…180. |
| `/search` | optional `q` | Opens search and pre-fills a non-empty query. |

URL-encode parameter values when constructing links. For example,
`https://m.parktrack.live/search?q=Lenina%20Street`.

## Backward compatibility

The following map links are also accepted:

- `https://m.parktrack.live/map?id=42`;
- `https://m.parktrack.live/map?zoneId=42`;
- `https://m.parktrack.live/map?q=station`;
- `https://m.parktrack.live/map/parking/42`;
- the corresponding `parktrack://map?...` links.

Both authority-style (`parktrack://parking/42`) and path-style
(`parktrack:/parking/42`) custom-scheme URIs are accepted.

## Authentication and fallback behavior

Only exact `https://m.parktrack.live` links, `parktrack://` links, and internal
relative paths are accepted as application destinations. Unknown or malformed
links safely fall back to `/map`. Protected sections preserve their destination
while the stored session is checked and through sign-in. The public `/login`,
`/register`, and `/password-reset` sections can open before the session check
finishes. External values passed through the internal `from` parameter are
sanitized and cannot be used as open redirects.

## Android App Links association

The Digital Asset Links document is stored at
`web/.well-known/assetlinks.json` and must be available as
`https://m.parktrack.live/.well-known/assetlinks.json` with an HTTP 200 response.
The Android manifest accepts HTTPS links only for the exact
`m.parktrack.live` host and also registers the `parktrack` custom scheme.

GitHub Pages deployment uploads hidden files explicitly so the `.well-known`
directory is retained in the published artifact.

## Local Web verification

Start the Web application from the repository root:

```shell
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

While it is running, both the association file and a direct application route
must be available:

```shell
curl -i http://127.0.0.1:8080/.well-known/assetlinks.json
curl -i http://127.0.0.1:8080/parking/42
```

Both requests should return HTTP 200. A release build also copies the document
to `build/web/.well-known/assetlinks.json`.
