import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/branding/tenant_branding.dart';
import 'accent_scheme.dart';

/// The app accent for the signed-in tenant: its brand colour when that clears the contrast gate,
/// otherwise [AccentScheme.stampRed] (also while branding is loading, failed, or absent).
final tenantAccentProvider = Provider<AccentScheme>((ref) {
  final branding = switch (ref.watch(tenantBrandingProvider)) {
    AsyncData(:final value) => value,
    _ => null,
  };
  // fromHex does not trim; the server value may carry whitespace (the web shell trims too).
  return AccentScheme.fromHex(branding?.primaryColor?.trim()) ?? AccentScheme.stampRed;
});
