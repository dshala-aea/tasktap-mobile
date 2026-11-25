// dart format width=100
/// Where the "Aggiorna" button sends the user: the policy's `storeUrl` when it is an https URL on an
/// official store host, otherwise the platform's generic store page. [androidPackageName] comes from the running
/// app (`PackageInfo.packageName`), never a hard-coded id.
Uri resolveStoreUri({String? policyUrl, required bool isIos, String? androidPackageName}) {
  final fromPolicy = _httpsUri(policyUrl);
  if (fromPolicy != null) return fromPolicy;
  if (isIos) return Uri.parse('https://apps.apple.com/');
  final id = androidPackageName?.trim() ?? '';
  if (id.isEmpty) return Uri.parse('https://play.google.com/store');
  return Uri.https('play.google.com', '/store/apps/details', {'id': id});
}

// https only, no user-info, and an exact store host: the value is operator-entered (or could be
// poisoned in transit) and the app hands it to the OS to open. Mirrors the API's validation.
const _allowedStoreHosts = {'apps.apple.com', 'itunes.apple.com', 'play.google.com'};

Uri? _httpsUri(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.toLowerCase() != 'https') return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (!_allowedStoreHosts.contains(uri.host.toLowerCase())) return null;
  return uri;
}
