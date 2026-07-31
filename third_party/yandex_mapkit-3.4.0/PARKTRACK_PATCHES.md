# ParkTrack Android patches

This directory is based on `yandex_mapkit` 3.4.0. It is vendored to preserve
the application's existing Dart API while applying Android compatibility
fixes that are not present in that published package.

- The Android Yandex MapKit dependency is upgraded from 4.4.0-full to
  4.19.0-full for 16 KB memory-page support.
- The Java bridge is adapted to MapKit 4.19.0 API signatures.
- Placemark bitmap decoding always uses `BitmapFactory.Options`, performs a
  bounds pass, and applies power-of-two downsampling above 1024 px.
- Android compile SDK is 36 and minimum SDK is 26.

Keep the `full` native MapKit variant when updating this fork. Re-run release
APK/AAB, `zipalign -P 16`, ELF `LOAD` alignment, R8, and runtime map checks
after every native MapKit upgrade.
