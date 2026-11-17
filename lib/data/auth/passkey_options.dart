import 'dart:convert';

/// Extracts a WebAuthn options object from whatever ZITADEL's gateway produced.
///
/// The shape is not stable across versions/deployments: the docs show the inner
/// options (`challenge`, `rpId`/`rp`, …); some gateways wrap them in a top-level
/// `publicKey`; and a Struct field can arrive JSON-encoded as a string. Accept
/// all of those, and return null when what is left cannot be options at all —
/// callers then surface a typed "malformed" failure instead of prompting the OS
/// with blanks.
///
/// [requiredKey] is the field that proves the object is the options we expected
/// (`challenge` for both flows); [wrapperKey] is the optional envelope.
Map<String, dynamic>? passkeyOptionsMap(
  dynamic raw, {
  required String wrapperKey,
  required String requiredKey,
}) {
  final outer = _asMap(raw);
  if (outer == null) return null;

  final wrapped = _asMap(outer[wrapperKey]);
  if (wrapped != null && wrapped[requiredKey] is String) return wrapped;

  if (outer[requiredKey] is String) return outer;

  return null;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
  }
  return null;
}
