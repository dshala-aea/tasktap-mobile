// dart format width=100
import 'package:url_launcher/url_launcher.dart';

/// Opens the device's own maps app (or a browser fallback) with directions to [address].
///
/// A single Google Maps search URL, not a platform-branched `geo:`/`maps://` scheme pair: Android
/// and iOS both resolve `https://www.google.com/maps/search/?api=1&query=...` to their installed
/// maps app when one exists, and to the Google Maps website otherwise — one URI, no per-platform
/// intent handling, no API key.
Future<bool> openMapsForAddress(String address) {
  final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address});
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
