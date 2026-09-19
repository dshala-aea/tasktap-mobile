/// Defensive readers for the shapes this backend actually puts on the wire.
///
/// Every numeric field in the `/api/app/*` contracts is declared `number|string` (and integers as
/// `integer|string`) in `docs/api/openapi.snapshot.json`, because .NET's serialiser renders some
/// decimals as strings. A client that casts instead of parsing throws on the first `"4.0"` and
/// takes the whole response with it — on a stock list or a customer record, that is the screen
/// going blank rather than one field being wrong.
///
/// Lives here rather than being copied per client: this is the third API client to need it, and a
/// parser duplicated three ways is one that will eventually disagree with itself.
library;

/// A double from a JSON number, a numeric string, or neither.
double? asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// As [asDouble], defaulting to 0 where the field is required and a missing value is meaningless
/// rather than meaningful. Prefer [asDouble] wherever null carries information — an absent
/// `stockMinimo` means "no minimum configured", which is not the same claim as zero.
double asDoubleOr0(Object? v) => asDouble(v) ?? 0;

/// An int from a JSON number, a numeric string, or neither.
int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// As [asInt], defaulting to 0. Same caveat as [asDoubleOr0].
int asIntOr0(Object? v) => asInt(v) ?? 0;

/// The rows out of a paginated response envelope.
///
/// The backend returns `PaginatedResultOf<T>` — `{items, page, pageSize, totalItems, totalPages}`
/// — from every list endpoint that takes a `page` parameter. Six client call sites asked Dio for
/// `List<dynamic>` from those routes instead, which throws a cast error on the response and takes
/// the whole screen with it. Two of them were the technician pickers on ticket creation and ticket
/// assignment, so both pickers came up empty and no technician could be selected at all.
///
/// The tell that this had gone unnoticed: `/api/Reports` was read correctly as an envelope in
/// `ticket_detail_api_client` and incorrectly as a bare list in `admin_api_client` — the same
/// endpoint, two shapes, in one app.
///
/// Tolerates a bare array too. Some routes are not paginated, and a helper that only understood
/// one shape would just move the crash.
List<Map<String, dynamic>> pagedItems(Object? body) {
  if (body is List) return body.cast<Map<String, dynamic>>();
  if (body is Map<String, dynamic>) {
    final items = body['items'];
    if (items is List) return items.cast<Map<String, dynamic>>();
  }
  return const [];
}
