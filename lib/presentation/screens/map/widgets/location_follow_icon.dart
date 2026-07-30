import 'package:flutter/material.dart';

class LocationFollowIcon extends StatelessWidget {
  const LocationFollowIcon({
    super.key,
    this.color = const Color(0xFF1967D2),
    this.size = 26,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          key: const Key('location_follow_top_line'),
          top: size * 0.02,
          child: Container(
            width: size * 0.1,
            height: size * 0.21,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(size * 0.05),
            ),
          ),
        ),
        Positioned(
          key: const Key('location_follow_bottom_line'),
          top: size * 0.77,
          child: Container(
            width: size * 0.1,
            height: size * 0.2,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(size * 0.05),
            ),
          ),
        ),
        Positioned(
          key: const Key('location_follow_arrow'),
          top: size * 0.18,
          child: Icon(
            Icons.navigation_rounded,
            size: size * 0.68,
            color: color,
          ),
        ),
      ],
    ),
  );
}
