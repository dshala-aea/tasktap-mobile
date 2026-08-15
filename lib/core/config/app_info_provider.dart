import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Holds app version info from PackageInfo.
class AppInfo {
  const AppInfo({required this.appName, required this.version, required this.buildNumber});

  final String appName;
  final String version;
  final String buildNumber;

  String get displayVersion => '$version+$buildNumber';
}

/// Reads app info from the platform at startup.
/// Cached for the app lifetime — no need to refresh.
final appInfoProvider = FutureProvider<AppInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppInfo(appName: info.appName, version: info.version, buildNumber: info.buildNumber);
});
