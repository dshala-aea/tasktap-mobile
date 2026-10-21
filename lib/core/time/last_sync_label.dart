import 'package:intl/intl.dart';

/// How a technician reads "when did this phone last refresh its data": "Mai", "Oggi alle 14:32",
/// "Ieri alle 09:10", "3 giorni fa", "12/10/2026".
///
/// Relative only where relative is unambiguous. Beyond a week the day count stops being something
/// anyone converts in their head, so the label switches to the date itself — the same `dd/MM/yyyy`
/// the rest of the app spells dates in.
///
/// The instant is shown in the device's own zone ([DateTime.toLocal]): this is when the sync
/// happened from the technician's point of view, not a business-zone calendar fact — unlike the
/// work-date helpers in `business_time.dart`, whose input is a civil date and must not be shifted.
///
/// [now] is for tests; production callers leave it out.
String formatLastSyncLabel(DateTime? lastSync, {DateTime? now}) {
  if (lastSync == null) return 'Mai';

  final local = lastSync.toLocal();
  final today = (now ?? DateTime.now()).toLocal();

  // Calendar-day difference on the y/m/d fields, not `Duration.inDays` over the instants: a DST
  // day is 23 or 25 hours, which would round "yesterday" to 0 days or to 26 hours.
  final daysAgo = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;

  final time = DateFormat('HH:mm').format(local);
  if (daysAgo == 0) return 'Oggi alle $time';
  if (daysAgo == 1) return 'Ieri alle $time';
  if (daysAgo > 1 && daysAgo < 7) return '$daysAgo giorni fa';
  // Also the future-date branch: a `syncedAt` ahead of the phone's clock (skew, or a device whose
  // date was set wrong) is still a real date, and a negative "N giorni fa" would be nonsense.
  return DateFormat('dd/MM/yyyy').format(local);
}
