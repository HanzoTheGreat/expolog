import 'dart:io';

import 'package:flutter/services.dart';

class BackgroundTimerBridge {
  static const MethodChannel _channel = MethodChannel('org.expolog.app/timer');

  static bool get isSupported => Platform.isAndroid;

  static Future<bool> requestNotificationPermission() async {
    if (!isSupported) return true;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startOrUpdate({
    required String sessionKey,
    required int nextTriggerAtSecs,
    required int repeatIntervalSecs,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('startOrUpdate', {
        'sessionKey': sessionKey,
        'nextTriggerMs': nextTriggerAtSecs * 1000,
        'repeatIntervalMs': repeatIntervalSecs * 1000,
      });
    } catch (_) {
      // UI bleibt auch ohne Hintergrund-Service voll benutzbar
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  static Future<void> testVibrate() async {
    if (!isSupported) {
      await HapticFeedback.heavyImpact();
      return;
    }
    try {
      await _channel.invokeMethod<void>('testVibrate');
    } catch (_) {}
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return true;
    try {
      final ignoring = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return ignoring ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAppSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }
}
