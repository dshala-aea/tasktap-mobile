// dart format width=100
import 'env.dart';

/// Hosts (and their subdomains) a server-provided OIDC issuer may live under. Compiled in on
/// purpose: the policy endpoint is reachable by anyone on the path to the API host, so a policy
/// alone must never be able to point sign-in (and the refresh token) at an arbitrary host.
const kAllowedIssuerHostSuffixes = ['advantedgeautomation.com', 'tasktap.it'];

/// Parses a comma-separated suffix list (the `OIDC_ISSUER_ALLOWED_SUFFIXES` dart-define):
/// trimmed, lowercased, empties and leading dots dropped.
List<String> parseIssuerSuffixes(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().replaceFirst(RegExp(r'^\.+'), '').isNotEmpty)
      part.trim().replaceFirst(RegExp(r'^\.+'), '').toLowerCase(),
];

/// The issuer to use (trimmed, lowercase host, no trailing slash), or null when [raw] is not an
/// acceptable server-provided issuer: https only, default port only, no user-info/query/fragment,
/// no IP literal, and a host that equals an allowed entry or is a subdomain of one (`.` boundary:
/// `eviladvantedgeautomation.com` fails). Allowed = [kAllowedIssuerHostSuffixes] + [extraSuffixes]
/// + the host of [compileTimeIssuer].
String? validatedIssuer(
  String? raw, {
  required String compileTimeIssuer,
  List<String>? extraSuffixes,
}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.isAbsolute) return null;
  if (uri.scheme.toLowerCase() != 'https') return null;
  final host = uri.host.toLowerCase();
  if (host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.hasQuery || uri.hasFragment) return null;
  if (uri.hasPort && uri.port != 443) return null;
  if (host.contains(':') || RegExp(r'^[0-9.]+$').hasMatch(host)) return null;

  final allowed = <String>[
    ...kAllowedIssuerHostSuffixes,
    ...(extraSuffixes ?? parseIssuerSuffixes(Env.oidcIssuerAllowedSuffixes)),
  ];
  final compiledHost = Uri.tryParse(compileTimeIssuer.trim())?.host.toLowerCase() ?? '';
  if (compiledHost.isNotEmpty) allowed.add(compiledHost);

  final ok = allowed.any((e) => host == e || host.endsWith('.$e'));
  if (!ok) return null;
  return normalizeIssuerString(text);
}

/// Issuer in the form used to compare two issuers: trimmed, lowercase scheme and host, no trailing
/// slash.
String normalizeIssuerString(String issuer) {
  var t = issuer.trim();
  final u = Uri.tryParse(t);
  if (u != null && u.hasAuthority && u.host.isNotEmpty) {
    t = u.replace(scheme: u.scheme.toLowerCase(), host: u.host.toLowerCase()).toString();
  }
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}
