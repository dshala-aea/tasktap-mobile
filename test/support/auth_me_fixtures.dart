// dart format width=100
// Fixture bodies of `GET /api/Auth/me`.
//
// `tenantTimeZone` is a top-level string field emitted by AuthController.cs (me action,
// ~L105-122: the `tenantTimeZone` member of the anonymous response object, resolved through
// IBusinessTime with a fallback to the default zone id). OpenAPI does NOT type this response,
// so the mobile contract gate cannot see the key: this fixture IS the contract. If the backend
// ever types auth/me, replace it with the snapshot check.

/// Marker for "leave the key out of the body" (distinct from an explicit null).
const Object authMeAbsent = Object();

/// The minimal valid body `EntitlementService.refresh` accepts, plus `tenantTimeZone` when given.
Map<String, dynamic> authMeBody({
  List<String> features = const ['clienti', 'team', 'sistema', 'rapportini', 'magazzino'],
  List<String> capabilities = const ['rapportini.report.write'],
  String seatType = 'field',
  Object? tenantTimeZone = authMeAbsent,
}) => {
  'features': features,
  'capabilities': capabilities,
  'seatType': seatType,
  if (!identical(tenantTimeZone, authMeAbsent)) 'tenantTimeZone': tenantTimeZone,
};
