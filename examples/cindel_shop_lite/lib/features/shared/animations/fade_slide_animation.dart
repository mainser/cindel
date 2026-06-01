import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class FadeSlideAnimation extends HookWidget {
  const FadeSlideAnimation({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.begin = -0.2, // Desplazamiento inicial (negativo = izquierda/arriba)
    this.isHorizontal = true,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double begin;
  final bool isHorizontal;

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(duration: duration);
    final opacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.12, 1, curve: Curves.easeOut),
    );
    final offset = Tween<Offset>(
      begin: isHorizontal ? Offset(begin, 0) : Offset(0, begin),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));

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
      child: SlideTransition(position: offset, child: child),
    );
  }
}
