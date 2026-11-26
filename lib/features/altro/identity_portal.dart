// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/app_version_policy_providers.dart' show storeLauncherProvider;
import '../../data/auth/auth_config_source.dart';

/// Where "Gestisci passkey e account" sends the technician: the identity service itself, opened in
/// the browser. Passkeys and the account live there, not in this app.
///
/// OPEN DECISION: the exact account / passkey page path on the identity service is not known, so
/// this is the issuer ROOT (from [AuthConfigSource], i.e. the server-provided issuer when valid,
/// else the compiled one — it follows an issuer move without a release). Replace by a deep link
/// once the owner names the page.
///
/// Null unless the issuer is an https URL: the app never hands a non-https address to the browser.
/// Never touches the network.
Future<Uri?> resolveIdentityPortalUri(AuthConfigSource source) async {
  final cfg = await source.load();
  final uri = Uri.tryParse(cfg.issuer.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) return null;
  return uri;
}

/// Overridable in widget tests.
final identityPortalUriProvider = Provider<Future<Uri?> Function()>((ref) {
  return () => resolveIdentityPortalUri(AuthConfigSource());
});

/// Opens the identity service in the system browser. Returns false when there is nothing safe to
/// open or the launch failed; the caller shows a calm message.
///
/// [launch] is the app's single "open a URL outside the app" seam (`storeLauncherProvider`:
/// `launchUrl(..., mode: LaunchMode.externalApplication)`, platform errors swallowed).
Future<bool> openIdentityPortal({
  required Future<Uri?> Function() resolve,
  required Future<bool> Function(Uri) launch,
}) async {
  final uri = await resolve();
  if (uri == null) return false;
  return launch(uri);
}

/// [openIdentityPortal] wired to the providers.
Future<bool> openIdentityPortalFrom(WidgetRef ref) => openIdentityPortal(
  resolve: ref.read(identityPortalUriProvider),
  launch: ref.read(storeLauncherProvider),
);
