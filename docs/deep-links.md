# ParkTrack app links

Supported host: `https://m.parktrack.live`

Android application ID: `com.parktrack.mobile`

## Supported URLs

- Map: `https://m.parktrack.live/map`
- Parking: `https://m.parktrack.live/parking/42`
- Search: `https://m.parktrack.live/search?q=Lenina%20Street`
- Destination with query parameters:
  `https://m.parktrack.live/destination?lat=61.789114&lon=34.359757&name=Station`

Unknown or malformed paths fall back to `/map`. Protected destinations are
remembered while authentication is in progress and restored afterwards.

## Android verification blocker

`web/.well-known/assetlinks.json` intentionally contains an empty array until
the Google Play App Signing SHA-256 certificate fingerprint is supplied. The
local signing report exposes the upload certificate, not the certificate used
by Google Play to sign production installs, so it must not be substituted.

Obtain the missing value in Google Play Console:

1. Open **Release > Setup > App integrity**.
2. Under **App signing key certificate**, copy the **SHA-256 certificate
   fingerprint** (not the upload key fingerprint).
3. Replace `web/.well-known/assetlinks.json` with:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.parktrack.mobile",
      "sha256_cert_fingerprints": ["GOOGLE_PLAY_APP_SIGNING_SHA256"]
    }
  }
]
```

After deployment, verify the exact public URL:

```sh
curl -fsS https://m.parktrack.live/.well-known/assetlinks.json
adb shell pm verify-app-links --re-verify com.parktrack.mobile
adb shell pm get-app-links com.parktrack.mobile
```

Test a warm or cold Android launch:

```sh
adb shell am start -W -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d "https://m.parktrack.live/parking/42" \
  com.parktrack.mobile
```

## Web and PWA routing

The app uses Flutter's path URL strategy. The GitHub Pages deployment copies
the built `index.html` to `404.html`, allowing direct requests for nested paths
to bootstrap Flutter while retaining the requested browser URL. The manifest
scope covers the entire host and `launch_handler` reuses an installed PWA
window when supported by the browser.
