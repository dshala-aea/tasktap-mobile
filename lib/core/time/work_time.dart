/// .NET `TimeSpan` JSON text: `HH:mm`, `H:mm:ss`, `HH:mm:ss.fffffff` and the
/// day form `D.HH:mm:ss`.
final _timeSpanShape = RegExp(
  r'^(?:(\d{1,7})\.)?(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,7}))?)?$',
);

/// Parses a .NET `TimeSpan` string. The fraction is truncated to whole
/// seconds, like the server. Returns null for null, empty, non-string or
/// malformed input, negative components, and ISO timestamps.
Duration? parseTimeSpan(Object? value) {
  if (value is! String) return null;
  final m = _timeSpanShape.firstMatch(value);
  if (m == null) return null;
  final days = m.group(1) == null ? 0 : int.parse(m.group(1)!);
  final hours = int.parse(m.group(2)!);
  final minutes = int.parse(m.group(3)!);
  final seconds = m.group(4) == null ? 0 : int.parse(m.group(4)!);
  if (hours > 23 || minutes > 59 || seconds > 59) return null;
  return Duration(days: days, hours: hours, minutes: minutes, seconds: seconds);
}

/// Formats [d] as `HH:mm:ss`, or `D.HH:mm:ss` from 24 h up (the form
/// `TimeSpan.Parse` accepts). The sub-second part is dropped.
String formatTimeSpan(Duration d) {
  if (d.isNegative) {
    throw ArgumentError.value(d, 'd', 'must not be negative');
  }
  final days = d.inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  final hms =
      '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  return days == 0 ? hms : '$days.$hms';
}

/// Combines a civil [workDate] (read by its y/m/d fields, so a local- or
/// UTC-flagged date gives the same result) with [timeOfDay].
///
/// The result is a UTC-flagged wall-clock carrier in the business zone: its
/// fields are the label, it is NOT an instant. Never call `.toLocal()` on it.
/// When an instant is needed, use `BusinessTime.instantOfLegacyLabel`.
DateTime combineWorkDate(DateTime workDate, Duration timeOfDay) =>
    DateTime.utc(workDate.year, workDate.month, workDate.day).add(timeOfDay);
