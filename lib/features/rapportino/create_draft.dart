import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/report_editor_providers.dart'
    show draftReportRepositoryProvider;

/// Creates a local rapportino draft with the identifiers this device actually knows.
///
/// ## What was wrong, stated accurately
///
/// Two screens created drafts with `tenantId: 'local'` and `insertedUserId: 'local-user'`,
/// duplicated between them. It is worth being precise about the damage, because the obvious
/// reading overstates it: **neither value is ever transmitted.** `SubmitReportRequest` carries no
/// tenant and no author, the attachment upload posts only the file, and the server derives both
/// from the bearer token. So these literals never reached payroll or an invoice.
///
/// What they did do:
///
/// 1. **Named nobody on screen.** `rapportino_view_screen` falls back to `insertedUserId` for the
///    technician line when a draft has no staff rows, so a real report displayed the string
///    `local-user` as the person who wrote it.
/// 2. **Left a trap in the table.** Sync writes real tenant ids into `draft_reports`, so the table
///    holds a mix of genuine ids and the literal `local`. Nothing filters on it *today* — the day
///    someone adds the tenant scoping a multi-tenant app eventually wants, every locally-created
///    draft silently disappears from the list. A fake value that currently matches nothing is
///    harder to find later than an absent one.
///
/// ## Where the real values come from
///
/// The author is the signed-in user. Unauthenticated, this **refuses** rather than inventing a
/// placeholder: a rapportino is authored by somebody, and a draft attributed to nobody is exactly
/// the shape of the `user-<timestamp>` bug this codebase already fixed once.
///
/// The tenant is read from the local mirror, which sync fills and which is single-tenant by
/// construction — every row on the device belongs to the signed-in user's tenant, so any synced
/// row answers the question. Before the first sync there is genuinely no answer, and the field is
/// left empty rather than filled with a plausible-looking constant. Empty reads as unknown; `local`
/// reads as a tenant that does not exist.
Future<String?> createLocalDraft(
  WidgetRef ref, {
  required String title,
  String locationId = '',
  String? ticketId,
  String? customerId,
  String? scheduleId,
  String? tenantId,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return null;

  // A caller creating the draft against a known entity already holds that entity's tenant, which
  // is better evidence than any row the mirror happens to return.
  final db = ref.read(appDatabaseProvider);
  final resolvedTenantId = tenantId ?? await resolveDeviceTenantId(db);

  final id = 'draft-${DateTime.now().microsecondsSinceEpoch}';
  await ref
      .read(draftReportRepositoryProvider)
      .createDraft(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: resolvedTenantId,
          createdAt: DateTime.now().toUtc(),
          title: title,
          insertedUserId: user.id,
          locationId: locationId,
          ticketId: Value(ticketId),
          customerId: Value(customerId),
          scheduleId: Value(scheduleId),
          isLocalOnly: const Value(true),
          stato: const Value('Bozza'),
        ),
      );

  return id;
}

/// The tenant every synced row on this device belongs to, or `''` before the first sync.
///
/// Tickets first because they are the most likely table to be populated for a technician, then two
/// fallbacks. Returning `''` is a real answer — "this device does not know yet" — and the server
/// assigns the true tenant on submit regardless.
Future<String> resolveDeviceTenantId(AppDatabase db) async {
  final ticket = await (db.select(db.tickets)..limit(1)).getSingleOrNull();
  if (ticket != null) return ticket.tenantId;

  final location = await (db.select(db.locations)..limit(1)).getSingleOrNull();
  if (location != null) return location.tenantId;

  final customer = await (db.select(db.customers)..limit(1)).getSingleOrNull();
  return customer?.tenantId ?? '';
}
