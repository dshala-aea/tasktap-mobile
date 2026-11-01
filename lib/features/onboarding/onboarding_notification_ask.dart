import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_service.dart';

/// Whether the notification permission can be asked on this device.
///
/// A provider rather than a direct static read so the welcome can be tested without Firebase.
final notificationAvailableProvider = Provider<bool>((ref) {
  return NotificationService.isAvailable;
});

/// The OS notification ask, behind a provider for the same reason.
final onboardingNotificationAskProvider = Provider<Future<bool> Function()>((ref) {
  return () => NotificationService.instance.ensurePermission();
});
