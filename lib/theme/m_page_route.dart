import 'package:flutter/material.dart';

enum MTransition { push, modal, fade }

/// Themed PageRoute used for navigation across the app.
///
/// Replaces a mix of MaterialPageRoute (no theme — feels stock) and
/// per-screen PageRouteBuilder (great where used, but inconsistent).
///
/// Honors the user's "remove animations" accessibility setting via
/// `MediaQuery.disableAnimations` — those users get instant cuts.
class MPageRoute<T> extends PageRouteBuilder<T> {
  MPageRoute({
    required Widget page,
    MTransition transition = MTransition.push,
    Duration? duration,
  }) : super(
          pageBuilder: (context, _, __) => page,
          transitionDuration: duration ?? _defaultDuration(transition),
          reverseTransitionDuration: duration ?? _defaultDuration(transition),
          opaque: transition != MTransition.modal,
          barrierColor: transition == MTransition.modal
              ? Colors.black54
              : null,
          transitionsBuilder: (context, animation, secondary, child) {
            // Respect the OS-level "remove animations" setting.
            if (MediaQuery.of(context).disableAnimations) return child;
            switch (transition) {
              case MTransition.push:
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: FadeTransition(opacity: animation, child: child),
                );
              case MTransition.modal:
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                );
              case MTransition.fade:
                return FadeTransition(opacity: animation, child: child);
            }
          },
        );

  static Duration _defaultDuration(MTransition t) {
    switch (t) {
      case MTransition.push:
        return const Duration(milliseconds: 320);
      case MTransition.modal:
        return const Duration(milliseconds: 360);
      case MTransition.fade:
        return const Duration(milliseconds: 240);
    }
  }
}
