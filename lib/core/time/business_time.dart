import 'package:intl/intl.dart';
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

/// Frame of every legacy `WorkDate/StartTime/EndTime` label the backend
/// writes. Independent of the tenant zone (plan Ruling 3).
const kLegacyLabelZoneId = 'Europe/Rome';

/// Tenant business-zone calendar logic. The only place that knows a zone.
/// [clock] is only ever read as an instant (`.toUtc()`).
class BusinessTime {
  BusinessTime(String zoneId, {DateTime Function()? clock})
    : zoneId = resolveBusinessZoneId(zoneId),
      _clock = clock ?? DateTime.now {
    location = tz.getLocation(this.zoneId);
  }

  BusinessTime.fallback({DateTime Function()? clock})
    : this(kDefaultBusinessZoneId, clock: clock);

  final String zoneId;
  late final tz.Location location;
  final DateTime Function() _clock;

  /// Plain `DateTime` (not `TZDateTime`) so `==` is symmetric with literals.
  static DateTime _plainUtc(tz.TZDateTime t) =>
      DateTime.fromMicrosecondsSinceEpoch(
        t.microsecondsSinceEpoch,
        isUtc: true,
      );

  tz.TZDateTime _nowInZone(tz.Location loc) =>
      tz.TZDateTime.from(_clock().toUtc(), loc);

  /// Half-open `[start, end)` UTC range of the business-zone calendar day
  /// [civilDate] (read by its y/m/d fields). End is local midnight of the next
  /// calendar date, so 23 h / 25 h days are exact. In a zone whose local
  /// midnight does not exist on that date (e.g. America/Havana) the start is
  /// shifted forward by the library.
  (DateTime startUtc, DateTime endUtc) utcRangeForBusinessDate(
    DateTime civilDate,
  ) {
    final start = tz.TZDateTime(
      location,
      civilDate.year,
      civilDate.month,
      civilDate.day,
    );
    final end = tz.TZDateTime(
      location,
      civilDate.year,
      civilDate.month,
      civilDate.day + 1,
    );
    return (_plainUtc(start), _plainUtc(end));
  }

  /// Civil date (`DateTime.utc(y, m, d)`) of the clock in the business zone.
  DateTime businessToday() {
    final n = _nowInZone(location);
    return DateTime.utc(n.year, n.month, n.day);
  }

  /// Civil date of the clock in the legacy label frame (Rome), whatever the
  /// business zone. Only for giving a bare legacy time-of-day its date.
  DateTime legacyToday() {
    final n = _nowInZone(tz.getLocation(kLegacyLabelZoneId));
    return DateTime.utc(n.year, n.month, n.day);
  }

  (DateTime, DateTime) todayRangeUtc() =>
      utcRangeForBusinessDate(businessToday());

  /// Formats [instant] as wall-clock time in the business zone. A non-null
  /// [locale] needs `initializeDateFormatting(locale)` first (otherwise
  /// `LocaleDataException`); null works with numeric patterns.
  String formatInZone(DateTime instant, String pattern, {String? locale}) {
    final z = tz.TZDateTime.from(instant.toUtc(), location);
    // DateFormat reads fields only. A UTC carrier cannot hit a device-zone
    // DST gap (a local-zone constructor would shift e.g. 02:30 to 03:30).
    final carrier = DateTime.utc(
        z.year, z.month, z.day, z.hour, z.minute, z.second, z.millisecond);
    return DateFormat(pattern, locale).format(carrier);
  }

  /// Instant of a legacy label (`civilDate` + [timeOfDay]) in the Rome frame,
  /// never the tenant zone. In the repeated autumn hour the library picks one
  /// of the two instants; in the spring gap it shifts forward. Removable once
  /// the backend exposes UTC instants on these DTOs.
  DateTime instantOfLegacyLabel(DateTime civilDate, Duration timeOfDay) {
    final civil = DateTime.utc(
      civilDate.year,
      civilDate.month,
      civilDate.day,
    ).add(timeOfDay);
    final rome = tz.getLocation(kLegacyLabelZoneId);
    return _plainUtc(
      tz.TZDateTime(
        rome,
        civil.year,
        civil.month,
        civil.day,
        civil.hour,
        civil.minute,
        civil.second,
        civil.millisecond,
      ),
    );
  }
}
