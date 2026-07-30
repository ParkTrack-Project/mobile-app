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
          top: size * 0.03,
          child: Container(
            width: size * 0.1,
            height: size * 0.16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(size * 0.05),
            ),
          ),
        ),
        Positioned(
          top: size * 0.38,
          child: Icon(
            Icons.navigation_rounded,
            size: size * 0.76,
            color: color,
          ),
        ),
      ],
    ),
  );
}
