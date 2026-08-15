import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/rapportino/create_draft.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late AppDatabase db;
  late _MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final user = AuthUser(
    id: 'real-user-id',
    email: 'mario@tasktap.io',
    accessToken: 't',
    refreshToken: 'r',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = _MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
  });

  tearDown(() async {
    await authStream.close();
    await db.close();
  });

  /// Runs [body] with a WidgetRef, since createLocalDraft takes one.
  Future<void> withRef(
    WidgetTester tester,
    Future<void> Function(WidgetRef ref) body, {
    required bool signedIn,
  }) async {
    when(() => repo.currentUser).thenReturn(signedIn ? user : null);

    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(repo),
        ],
        child: Consumer(
          builder: (_, ref, _) {
            // Watched, not merely captured: currentUserProvider reads authStateProvider, a
            // StreamProvider that only subscribes once something listens. Without this the first
            // read returns null and every signed-in case looks signed out.
            ref.watch(currentUserProvider);
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    if (signedIn) authStream.add(user);
    await tester.pump();
    await tester.pump();
    await body(captured);
  }

  Future<void> seedTicket(String tenantId) async {
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't1',
            tenantId: tenantId,
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Perdita',
            customerId: 'c1',
            locationId: 'l1',
            statusId: 1,
            typeId: 1,
          ),
        );
  }

  testWidgets('stamps the signed-in user, not a placeholder', (tester) async {
    await withRef(tester, signedIn: true, (ref) async {
      await seedTicket('tenant-real');
      final id = await createLocalDraft(ref, title: 'Nuovo rapportino');
      expect(id, isNotNull);

      final draft = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();

      // Was the literal 'local-user', which the read-only view rendered verbatim as the person
      // who wrote the report.
      expect(draft.insertedUserId, 'real-user-id');
    });
  });

  testWidgets('takes the tenant from the synced mirror', (tester) async {
    await withRef(tester, signedIn: true, (ref) async {
      await seedTicket('tenant-real');
      final id = await createLocalDraft(ref, title: 'X');
      final draft = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();

      // Was 'local' — a tenant that does not exist, sitting in a table where sync writes real
      // ones. The day anything filters by tenant, those drafts vanish.
      expect(draft.tenantId, 'tenant-real');
    });
  });

  testWidgets('an explicit tenant beats the mirror lookup', (tester) async {
    await withRef(tester, signedIn: true, (ref) async {
      await seedTicket('tenant-from-mirror');
      final id = await createLocalDraft(ref, title: 'X', tenantId: 'tenant-from-ticket');
      final draft = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();

      expect(draft.tenantId, 'tenant-from-ticket');
    });
  });

  testWidgets('before the first sync the tenant is empty, never invented', (tester) async {
    await withRef(tester, signedIn: true, (ref) async {
      // Nothing seeded: a fresh install that has not synced.
      final id = await createLocalDraft(ref, title: 'X');
      final draft = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();

      // Empty reads as "not known yet". A plausible-looking constant reads as an answer, and the
      // server assigns the real tenant on submit either way.
      expect(draft.tenantId, '');
    });
  });

  testWidgets('refuses to create a draft when signed out', (tester) async {
    await withRef(tester, signedIn: false, (ref) async {
      final id = await createLocalDraft(ref, title: 'X');

      // A rapportino is authored by somebody. Inventing an author is the shape of the
      // user-<timestamp> bug this codebase already fixed once.
      expect(id, isNull);
      expect(await db.select(db.draftReports).get(), isEmpty);
    });
  });

  testWidgets('carries the ticket context through', (tester) async {
    await withRef(tester, signedIn: true, (ref) async {
      await seedTicket('tenant-real');
      final id = await createLocalDraft(
        ref,
        title: 'Rapportino — Perdita',
        locationId: 'l1',
        ticketId: 't1',
        customerId: 'c1',
      );
      final draft = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();

      expect(draft.ticketId, 't1');
      expect(draft.customerId, 'c1');
      expect(draft.locationId, 'l1');
    });
  });

  testWidgets('two drafts created in the same millisecond get distinct ids', (tester) async {
    await withRef(tester, signedIn: true, (ref) async {
      // The old id used millisecondsSinceEpoch. Two taps inside one millisecond — a double-tap on
      // a fast device — produced the same id and the second insert collided with the first.
      final a = await createLocalDraft(ref, title: 'A');
      final b = await createLocalDraft(ref, title: 'B');

      expect(a, isNot(b));
      expect(await db.select(db.draftReports).get(), hasLength(2));
    });
  });
}
