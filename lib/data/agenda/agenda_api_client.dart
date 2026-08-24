// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../api/json_parse.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AgendaApiClient — a technician's own quick-task list
//
// `/api/agenda` (AgendaController.cs) has been live on the server — list by date, list by range,
// create, update, delete, complete — with full CRUD and permission checks, and no client, mobile
// or web, has ever called any of it. This is personal to-do data: "call the supplier back", "pick
// up the part before the next stop" — a different aggregate from Schedule (`calendario/`, its own
// table, AgendaItems), which is dispatcher-assigned work. Do not conflate the two.
//
// Online-only, deliberately, unlike most of this app's field-capture screens. Those queue writes
// because a technician records what happened *at* a job, mid-task, sometimes with no signal — the
// write cannot wait for connectivity to come back without losing the moment. An agenda item is
// typed by the same person who will read it back, generally at a desk or in the cab with signal,
// never as a record of something that just happened on site. The failure mode that justifies a
// Drift cache + sync queue elsewhere does not apply here, and a queue would add a second source of
// truth this pocket-notepad feature does not need. Same call `admin/squadre` already made for its
// own simple CRUD: fetch, mutate, refetch — no local cache, no queue.
//
// `Priority` is a bare `int` on the wire (`AgendaItem.Priority`, default 0) — no backend enum, no
// `[JsonStringEnumConverter]`, nothing in `PermissionCatalogue`/`WorkEnums` naming a scale. 0–3
// labelled Bassa/Media/Alta/Urgente below is a client-side convention only, chosen to match the
// language technicians already see on ticket priority — never assume the server enforces it.
// ══════════════════════════════════════════════════════════════════════════════

/// Client-side priority labels for [AgendaItemDto.priority]. The backend stores a bare int with no
/// documented scale (see file doc) — this is a UI convention, not a contract.
const List<String> kAgendaPriorityLabels = ['Bassa', 'Media', 'Alta', 'Urgente'];

/// Clamps an arbitrary server int into the label range, so a value outside 0–3 (never sent by this
/// client, but nothing stops another one) still renders as something rather than throwing.
String agendaPriorityLabel(int priority) =>
    kAgendaPriorityLabels[priority.clamp(0, kAgendaPriorityLabels.length - 1)];

/// `date` as `yyyy-MM-dd` — the wire format .NET's `DateOnly` converter both writes and accepts.
String formatDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One personal agenda item, as the server states it.
class AgendaItemDto {
  const AgendaItemDto({
    required this.id,
    required this.date,
    this.timeStart,
    this.timeEnd,
    required this.title,
    this.description,
    this.priority = 0,
    this.isCompleted = false,
    this.completedAt,
    this.ticketId,
    this.scheduleId,
  });

  final String id;

  /// Calendar date only — the time-of-day components are always zero.
  final DateTime date;

  /// `HH:mm:ss`, straight off the wire (.NET's `TimeOnly` converter). Null means "no time set",
  /// not midnight.
  final String? timeStart;
  final String? timeEnd;

  final String title;
  final String? description;

  /// See the file doc: a bare int, no backend-defined scale.
  final int priority;

  final bool isCompleted;
  final DateTime? completedAt;

  /// Optional links back to a ticket or a dispatcher schedule. This client never sets either —
  /// they exist so a future screen (or the backend itself, for its own agenda entries) can link
  /// an item to other work without a schema change.
  final String? ticketId;
  final String? scheduleId;

  static DateTime? _parseDateOnly(Object? v) {
    if (v is! String || v.isEmpty) return null;
    final parts = v.split('-');
    if (parts.length != 3) return DateTime.tryParse(v);
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return DateTime.tryParse(v);
    return DateTime(y, m, d);
  }

  factory AgendaItemDto.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final completedRaw = json['completedAt'];
    return AgendaItemDto(
      id: id is String ? id : '',
      date: _parseDateOnly(json['date']) ?? DateTime.now(),
      timeStart: json['timeStart'] as String?,
      timeEnd: json['timeEnd'] as String?,
      title: title is String ? title : '',
      description: json['description'] as String?,
      priority: asIntOr0(json['priority']),
      isCompleted: json['isCompleted'] as bool? ?? false,
      completedAt: completedRaw is String ? DateTime.tryParse(completedRaw) : null,
      ticketId: json['ticketId'] as String?,
      scheduleId: json['scheduleId'] as String?,
    );
  }
}

class AgendaApiClient {
  AgendaApiClient(this._dio);

  final Dio _dio;

  /// Items in `[from, to]` (inclusive), oldest first — so anything overdue floats above what's
  /// upcoming, which is the reading order a to-do list wants. GET /api/agenda/range; the backend
  /// clamps pageSize to 100, which is far beyond what one technician's own list should ever hold.
  Future<List<AgendaItemDto>> fetchAgenda({required DateTime from, required DateTime to}) async {
    // `dynamic`, not `Map<String, dynamic>`: /range always answers with the paginated envelope in
    // practice, but [pagedItems] also tolerates a bare array, and typing the response any
    // narrower turns that tolerance into a cast exception before pagedItems ever runs.
    final res = await _dio.get<dynamic>(
      '/api/agenda/range',
      queryParameters: {'from': formatDateOnly(from), 'to': formatDateOnly(to), 'pageSize': 100},
    );
    return [for (final row in pagedItems(res.data)) AgendaItemDto.fromJson(row)];
  }

  /// POST /api/agenda. Returns the new item's id. `userId` is left off the payload on purpose —
  /// the backend defaults it to the caller (`AgendaController.Create`), which is exactly right for
  /// "my own" quick tasks.
  Future<String> createAgendaItem({
    required DateTime date,
    String? timeStart,
    String? timeEnd,
    required String title,
    String? description,
    int priority = 0,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/agenda',
      data: {
        'date': formatDateOnly(date),
        'timeStart': ?timeStart,
        'timeEnd': ?timeEnd,
        'title': title,
        if (description != null && description.isNotEmpty) 'description': description,
        'priority': priority,
      },
    );
    return res.data!['id'] as String;
  }

  /// PUT /api/agenda/{id}. `AgendaController.Update` overwrites date/timeStart/timeEnd/title/
  /// priority unconditionally and keeps the existing description when it is omitted — but *not*
  /// timeEnd, which is always replaced. Pass the item's current [timeEnd] back explicitly if it
  /// should survive the edit; omitting it clears it server-side.
  Future<void> updateAgendaItem(
    String id, {
    required DateTime date,
    String? timeStart,
    String? timeEnd,
    required String title,
    String? description,
    int priority = 0,
  }) async {
    await _dio.put(
      '/api/agenda/$id',
      data: {
        'date': formatDateOnly(date),
        'timeStart': ?timeStart,
        'timeEnd': ?timeEnd,
        'title': title,
        'description': ?description,
        'priority': priority,
      },
    );
  }

  /// POST /api/agenda/{id}/complete. One-directional: `AgendaController` has no way to mark an
  /// item incomplete again once this has been called.
  Future<void> completeAgendaItem(String id) async {
    await _dio.post('/api/agenda/$id/complete');
  }

  /// DELETE /api/agenda/{id}.
  Future<void> deleteAgendaItem(String id) async {
    await _dio.delete('/api/agenda/$id');
  }
}

final agendaApiClientProvider = Provider<AgendaApiClient>((ref) {
  return AgendaApiClient(ref.watch(dioProvider));
});

/// The window a personal agenda list shows: a month of recent history (so a missed item is not
/// silently gone) through half a year out. Online-only — see the file doc.
final agendaListProvider = FutureProvider.autoDispose<List<AgendaItemDto>>((ref) {
  final today = DateTime.now();
  final from = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 30));
  final to = DateTime(today.year, today.month, today.day).add(const Duration(days: 180));
  return ref.watch(agendaApiClientProvider).fetchAgenda(from: from, to: to);
});
