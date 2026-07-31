import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/presentation/screens/map/my_location_camera_state.dart';

void main() {
  test(
    'my location button centers first, follows second, then zooms out of follow',
    () {
      expect(
        nextMyLocationButtonAction(
          mode: MyLocationCameraMode.free,
          currentZoom: 14,
          targetZoom: 17,
        ),
        MyLocationButtonAction.centerWithoutZoom,
      );
      expect(
        nextMyLocationButtonAction(
          mode: MyLocationCameraMode.centered,
          currentZoom: 14,
          targetZoom: 17,
        ),
        MyLocationButtonAction.enableFollowing,
      );
      expect(
        nextMyLocationButtonAction(
          mode: MyLocationCameraMode.following,
          currentZoom: 14,
          targetZoom: 17,
        ),
        MyLocationButtonAction.disableFollowingAndZoom,
      );
    },
  );

  test('my location button toggles follow when zoom is already at target', () {
    expect(isLocationCameraZoomTarget(17.005, 17), isTrue);
    expect(isLocationCameraZoomTarget(16.98, 17), isFalse);
    expect(
      nextMyLocationButtonAction(
        mode: MyLocationCameraMode.following,
        currentZoom: 17,
        targetZoom: 17,
      ),
      MyLocationButtonAction.disableFollowing,
    );
  });

  test('camera updates reset location mode only after user gestures', () {
    expect(
      locationCameraModeAfterMapCameraUpdate(
        mode: MyLocationCameraMode.centered,
        userGesture: false,
      ),
      MyLocationCameraMode.centered,
    );
    expect(
      locationCameraModeAfterMapCameraUpdate(
        mode: MyLocationCameraMode.following,
        userGesture: false,
      ),
      MyLocationCameraMode.following,
    );
    expect(
      locationCameraModeAfterMapCameraUpdate(
        mode: MyLocationCameraMode.following,
        userGesture: true,
      ),
      MyLocationCameraMode.free,
    );
  });
}
