import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class FadeScaleAnimation extends HookWidget {
  const FadeScaleAnimation({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutBack,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(duration: duration);
    final curvedAnimation = CurvedAnimation(parent: controller, curve: curve);
    final opacity = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    useEffect(
      () {
        var cancelled = false;

        unawaited(
          Future<void>.delayed(delay, () {
            if (!cancelled) {
              unawaited(controller.forward());
            }
          }),
        );

        return () {
          cancelled = true;
        };
      },
      [controller, delay],
    );

    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.5, end: 1).animate(curvedAnimation),
        child: child,
      ),
    );
  }
}
