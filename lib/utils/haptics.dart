import 'package:flutter/services.dart';

/// Wrapper around [HapticFeedback] that gates every call on a runtime flag.
/// `enabled` is mirrored from `SettingsNotifier.hapticsEnabled` so the master
/// toggle in settings covers every call site in the app.
class Haptics {
  Haptics._();

  static bool enabled = true;

  static Future<void> selection() {
    if (!enabled) return Future.value();
    return HapticFeedback.selectionClick();
  }

  static Future<void> light() {
    if (!enabled) return Future.value();
    return HapticFeedback.lightImpact();
  }

  static Future<void> medium() {
    if (!enabled) return Future.value();
    return HapticFeedback.mediumImpact();
  }

  static Future<void> heavy() {
    if (!enabled) return Future.value();
    return HapticFeedback.heavyImpact();
  }
}
