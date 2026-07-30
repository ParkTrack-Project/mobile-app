enum MyLocationCameraMode { free, centered, following }

enum MyLocationButtonAction {
  centerWithoutZoom,
  enableFollowing,
  disableFollowing,
  disableFollowingAndZoom,
}

const double myLocationCameraZoomTolerance = 0.01;

MyLocationButtonAction nextMyLocationButtonAction({
  required MyLocationCameraMode mode,
  required double currentZoom,
  required double targetZoom,
}) {
  switch (mode) {
    case MyLocationCameraMode.free:
      return MyLocationButtonAction.centerWithoutZoom;
    case MyLocationCameraMode.centered:
      return MyLocationButtonAction.enableFollowing;
    case MyLocationCameraMode.following:
      return (currentZoom - targetZoom).abs() <= myLocationCameraZoomTolerance
          ? MyLocationButtonAction.disableFollowing
          : MyLocationButtonAction.disableFollowingAndZoom;
  }
}

bool isLocationCameraZoomTarget(double currentZoom, double targetZoom) =>
    (currentZoom - targetZoom).abs() <= myLocationCameraZoomTolerance;

MyLocationCameraMode locationCameraModeAfterMapCameraUpdate({
  required MyLocationCameraMode mode,
  required bool userGesture,
}) => userGesture ? MyLocationCameraMode.free : mode;
