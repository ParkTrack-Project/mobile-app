import 'package:flutter/material.dart';

class MapBottomPanelSwitcher extends StatelessWidget {
  const MapBottomPanelSwitcher({
    super.key,
    required this.transitionKey,
    this.child,
    this.expand = false,
  });

  final Object transitionKey;
  final Widget? child;
  final bool expand;

  static const duration = Duration(milliseconds: 320);
  static const reverseDuration = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final current = child;
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: expand ? StackFit.expand : StackFit.loose,
        alignment: Alignment.bottomCenter,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: current == null
          ? const SizedBox.shrink(key: ValueKey('bottom_panel_hidden'))
          : KeyedSubtree(key: ValueKey(transitionKey), child: current),
    );
  }
}
