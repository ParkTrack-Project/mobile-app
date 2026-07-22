# Android App Links Configuration

To enable automatic verification for App Links on Android, you must add the production SHA-256 fingerprint to `web/.well-known/assetlinks.json`.

## Current Blocker
The production SHA-256 fingerprint is currently missing in the repository. 

## How to get the fingerprint
If the app is published via Google Play with App Signing enabled:
1. Go to the [Google Play Console](https://play.google.com/console/).
2. Select your app.
3. Go to **Setup** > **App integrity**.
4. Find the **App signing key certificate** section.
5. Copy the **SHA-256 certificate fingerprint**.

If you are using a local keystore:
Run the following command:
```bash
keytool -list -v -keystore path/to/your/keystore.jks
```
Then find the SHA-256 value.

## Update assetlinks.json
Once you have the fingerprint, update `web/.well-known/assetlinks.json`:
```json
"sha256_cert_fingerprints": [
  "PASTE_YOUR_FINGERPRINT_HERE"
]
```
