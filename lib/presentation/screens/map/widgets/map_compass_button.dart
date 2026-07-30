import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color _lightMapControlSurface = Color(0xF2FFFFFF);
const Color _darkMapControlSurface = Color(0xF22B2D31);
const Color _lightMapControlDivider = Color(0x1F000000);
const Color _darkMapControlDivider = Color(0xFF62656B);

Color mapControlSurfaceColor(BuildContext context) =>
    mapControlSurfaceColorFor(Theme.of(context).brightness);

Color mapControlDividerColor(BuildContext context) =>
    mapControlDividerColorFor(Theme.of(context).brightness);

@visibleForTesting
Color mapControlSurfaceColorFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? _darkMapControlSurface
    : _lightMapControlSurface;

@visibleForTesting
Color mapControlDividerColorFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? _darkMapControlDivider
    : _lightMapControlDivider;

class MapCompassButton extends StatefulWidget {
  const MapCompassButton({
    super.key,
    required this.azimuth,
    required this.onPressed,
    required this.tooltip,
  });

  final double azimuth;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  State<MapCompassButton> createState() => _MapCompassButtonState();
}

class _MapCompassButtonState extends State<MapCompassButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 80),
        curve: Curves.linear,
        child: DecoratedBox(
          key: const Key('map_compass_button_surface'),
          decoration: BoxDecoration(
            color: mapControlSurfaceColor(context),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox.square(
            dimension: 52,
            child: Center(child: _CompassIcon(azimuth: widget.azimuth)),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(message: widget.tooltip, child: button),
    );
  }
}

class _CompassIcon extends StatelessWidget {
  const _CompassIcon({required this.azimuth});

  final double azimuth;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      key: const Key('map_compass_rotation'),
      angle: -azimuth * math.pi / 180,
      child: const CustomPaint(
        key: Key('map_compass_icon'),
        size: Size(18, 24),
        painter: _CompassIconPainter(),
      ),
    );
  }
}

class _CompassIconPainter extends CustomPainter {
  const _CompassIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 44);

    canvas.drawPath(
      Path()
        ..moveTo(5, 22)
        ..lineTo(16, 0)
        ..lineTo(28, 22)
        ..close(),
      Paint()..color = const Color(0xFFFF2F27),
    );
    canvas.drawPath(
      Path()
        ..moveTo(5, 22)
        ..lineTo(16, 44)
        ..lineTo(28, 22)
        ..close(),
      Paint()..color = const Color(0xFFD1D3D4),
    );
    canvas.drawCircle(
      const Offset(16.25, 22.25),
      4,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassIconPainter oldDelegate) => false;
}
