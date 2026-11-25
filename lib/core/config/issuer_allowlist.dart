// dart format width=100
import 'env.dart';

/// The IdP hosts a server-provided OIDC issuer may use: EXACT hosts, no subdomain matching (a
/// dangling record on some other subdomain must not be able to receive sign-in). Compiled in on
/// purpose: the policy endpoint is reachable by anyone on the path to the API host, so a policy
/// alone must never be able to point sign-in (and the refresh token) at an arbitrary host.
const kAllowedIssuerHosts = ['auth.tasktap.it', 'id.advantedgeautomation.com'];

/// Parses a comma-separated host list (the `OIDC_ISSUER_ALLOWED_HOSTS` dart-define): trimmed,
/// lowercased, empties dropped.
List<String> parseIssuerHosts(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim().toLowerCase(),
];

/// The issuer to use (trimmed, lowercase host, no trailing slash), or null when [raw] is not an
/// acceptable server-provided issuer: https only, default port only, no user-info/query/fragment,
/// no IP literal, and a lowercased host EXACTLY equal to an allowed host. Allowed =
/// [kAllowedIssuerHosts] + [extraHosts] (default: the `OIDC_ISSUER_ALLOWED_HOSTS` define) + the
/// host of [compileTimeIssuer].
String? validatedIssuer(
  String? raw, {
  required String compileTimeIssuer,
  List<String>? extraHosts,
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
    ...kAllowedIssuerHosts,
    ...(extraHosts ?? parseIssuerHosts(Env.oidcIssuerAllowedHosts)),
  ];
  final compiledHost = Uri.tryParse(compileTimeIssuer.trim())?.host.toLowerCase() ?? '';
  if (compiledHost.isNotEmpty) allowed.add(compiledHost);

  if (!allowed.contains(host)) return null;
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
