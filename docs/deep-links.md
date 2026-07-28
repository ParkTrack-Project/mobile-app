# ParkTrack deep links

ParkTrack supports verified Android App Links on `m.parktrack.live` and the
`parktrack://` custom scheme. Both forms open the same application sections.

| Section | HTTPS App Link | Custom scheme |
| --- | --- | --- |
| Map | `https://m.parktrack.live/map` | `parktrack://map` |
| Parking card | `https://m.parktrack.live/parking/42` | `parktrack://parking/42` |
| Destination | `https://m.parktrack.live/destination?lat=61.789114&lon=34.359757&name=Station` | `parktrack://destination?lat=61.789114&lon=34.359757&name=Station` |
| Search | `https://m.parktrack.live/search?q=station` | `parktrack://search?q=station` |
| Profile | `https://m.parktrack.live/profile` | `parktrack://profile` |
| Edit profile | `https://m.parktrack.live/profile/edit` | `parktrack://profile/edit` |
| Sign in | `https://m.parktrack.live/login` | `parktrack://login` |
| Registration | `https://m.parktrack.live/register` | `parktrack://register` |
| Password reset | `https://m.parktrack.live/password-reset` | `parktrack://password-reset` |

Backward-compatible map links are also accepted:

- `https://m.parktrack.live/map?id=42`;
- `https://m.parktrack.live/map?zoneId=42`;
- `https://m.parktrack.live/map?q=station`;
- `https://m.parktrack.live/map/parking/42`;
- the corresponding `parktrack://map?...` links.

Only exact `https://m.parktrack.live` links, `parktrack://` links, and internal
relative paths are accepted as application destinations. Unknown or malformed
links safely fall back to `/map`. Protected sections preserve their destination
through authentication.
