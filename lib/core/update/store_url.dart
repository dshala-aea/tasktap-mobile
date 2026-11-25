// dart format width=100
/// Where the "Aggiorna" button sends the user: the policy's `storeUrl` when it is a usable https
/// URL, otherwise the platform's generic store page. [androidPackageName] comes from the running
/// app (`PackageInfo.packageName`), never a hard-coded id.
Uri resolveStoreUri({String? policyUrl, required bool isIos, String? androidPackageName}) {
  final fromPolicy = _httpsUri(policyUrl);
  if (fromPolicy != null) return fromPolicy;
  if (isIos) return Uri.parse('https://apps.apple.com/');
  final id = androidPackageName?.trim() ?? '';
  if (id.isEmpty) return Uri.parse('https://play.google.com/store');
  return Uri.https('play.google.com', '/store/apps/details', {'id': id});
}

// https only: the value is operator-entered, and the app hands it to the OS to open.
Uri? _httpsUri(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}
