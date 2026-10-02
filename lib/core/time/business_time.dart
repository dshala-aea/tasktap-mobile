import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Fallback business zone when the tenant zone is unknown or invalid.
const kDefaultBusinessZoneId = 'Europe/Rome';

bool _tzInitialized = false;

/// Loads the bundled IANA database once. No network, no platform channel.
void ensureTimeZonesInitialized() {
  if (_tzInitialized) return;
  tzdata.initializeTimeZones();
  _tzInitialized = true;
}

/// Returns [candidate] when it is an exact (case-sensitive) IANA id known to
/// the bundled database, otherwise [kDefaultBusinessZoneId]. Never consults
/// the device zone.
String resolveBusinessZoneId(String? candidate) {
  if (candidate == null || candidate.trim().isEmpty) {
    return kDefaultBusinessZoneId;
  }
  ensureTimeZonesInitialized();
  return tz.timeZoneDatabase.locations.containsKey(candidate)
      ? candidate
      : kDefaultBusinessZoneId;
}

final _dateOnlyShape = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// Parses the leading `yyyy-MM-dd` of a date or timestamp string as a civil
/// date, returned as `DateTime.utc(y, m, d)`. Any time part or offset is
/// ignored on purpose; the value is a calendar label, not an instant.
DateTime? parseDateOnly(Object? raw) {
  if (raw is! String || raw.length < 10) return null;
  if (raw.length > 10 && !'Tt '.contains(raw[10])) return null;
  final m = _dateOnlyShape.firstMatch(raw);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final date = DateTime.utc(y, mo, d);
  if (date.year != y || date.month != mo || date.day != d) return null;
  return date;
}
