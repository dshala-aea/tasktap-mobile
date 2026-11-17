// dart format width=100
// SessionEnder — the audit's F1 in assertion form: the FORCED path must delete nothing.
//
// A forced sign-out fires on a confirmed `invalid_grant`, routinely on the first flush after a
// long offline period — i.e. with every queue full. If it wiped Drift it would destroy exactly the
// work the flush was trying to send. Only the consented paths (manual logout, recovery-screen
// discard) may wipe.
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/auth/session_ender.dart';
import 'package:tasktap_mobile/data/auth/session_recovery.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart'
    show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';

class _FakeAuth implements IAuthRepository {
  _FakeAuth({this.user});

  final AuthUser? user;
  int signOutCalls = 0;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get authStateChanges => const Stream.empty();

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

const _sub = 'zitadel-sub-abc';

AuthUser _user() => AuthUser(
  id: _sub,
  email: 'tecnico@example.it',
  // Empty token: the FCM unregister guard (`token == null || token.isEmpty`) makes the testable
  // path skip the platform channel entirely.
  accessToken: '',
  refreshToken: 'refresh',
  expiresAt: DateTime.utc(2030),
);

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: 'draft-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Rapportino',
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          isLocalOnly: const Value(true),
        ),
      );
  await db
      .into(db.pendingTickets)
      .insert(
        PendingTicketsCompanion.insert(
          id: 'ticket-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Ticket',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
        ),
      );
  await db
      .into(db.pendingTicketAttachments)
      .insert(
        PendingTicketAttachmentsCompanion.insert(
          id: 'att-1',
          createdAt: DateTime.utc(2026, 6, 1),
          ticketId: 'ticket-1',
          localPath: '/tmp/a.jpg',
          fileName: 'a.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 10,
        ),
      );
  // Ten days old: the work that is most obviously at risk.
  await db
      .into(db.workSessions)
      .insert(
        WorkSessionsCompanion.insert(
          id: 'ws-1',
          eventTime: DateTime.utc(2026, 10, 11, 8),
          eventType: 'ingresso',
        ),
      );
  await db
      .into(db.cantierePunches)
      .insert(
        CantierePunchesCompanion.insert(
          id: 'cp-1',
          eventTime: DateTime.utc(2026, 10, 11, 9),
          eventType: 'ingresso',
        ),
      );
}

/// Every table a wipe would empty. Asserted as a set so a table added later cannot be forgotten
/// silently when this test is next edited.
Future<Map<String, int>> _rowCounts(AppDatabase db) async => {
  'draftReports': (await db.select(db.draftReports).get()).length,
  'pendingTickets': (await db.select(db.pendingTickets).get()).length,
  'pendingTicketAttachments': (await db.select(db.pendingTicketAttachments).get()).length,
  'workSessions': (await db.select(db.workSessions).get()).length,
  'cantierePunches': (await db.select(db.cantierePunches).get()).length,
};

void main() {
  late AppDatabase db;
  late _FakeAuth auth;
  late int voiceWipes;
  late int zoneResets;
  late SharedPreferences prefs;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    auth = _FakeAuth(user: _user());
    voiceWipes = 0;
    zoneResets = 0;
    SharedPreferences.setMockInitialValues({
      internalUserIdPrefsKey: '11111111-1111-1111-1111-111111111111',
      'unrelated.pref': 'kept-by-the-forced-path',
    });
    prefs = await SharedPreferences.getInstance();
    await _seed(db);
  });

  tearDown(() => db.close());

  SessionEnder ender() => SessionEnder(
    repo: auth,
    db: db,
    resetBusinessZone: () async => zoneResets++,
    wipePendingVoice: () async => voiceWipes++,
  );

  test('FORCED sign-out deletes nothing: every queue survives and the owner is recorded', () async {
    final before = await _rowCounts(db);

    await ender().endForced();

    expect(await _rowCounts(db), before, reason: 'the forced path must never wipe Drift');
    expect(auth.signOutCalls, 1, reason: 'credentials do go');
    expect(voiceWipes, 0, reason: 'pending audio is unsent work too');
    expect(zoneResets, 0, reason: 'no wipe means no zone reset');
    expect(prefs.getString('unrelated.pref'), 'kept-by-the-forced-path');
    expect(prefs.getString(sessionRetainedOwnerSubKey), _sub);
    expect(
      prefs.getString(sessionRetainedOwnerInternalIdKey),
      '11111111-1111-1111-1111-111111111111',
    );
  });

  test('forced sign-out without a readable session records no owner', () async {
    final anonymous = SessionEnder(
      repo: _FakeAuth(),
      db: db,
      resetBusinessZone: () async => zoneResets++,
      wipePendingVoice: () async => voiceWipes++,
    );

    await anonymous.endForced();

    expect(await _rowCounts(db), {
      'draftReports': 1,
      'pendingTickets': 1,
      'pendingTicketAttachments': 1,
      'workSessions': 1,
      'cantierePunches': 1,
    });
    expect(prefs.getString(sessionRetainedOwnerSubKey), isNull);
  });

  test('MANUAL logout still wipes: credentials, Drift, prefs, voice and zone', () async {
    await ender().end();

    expect(auth.signOutCalls, 1);
    expect(voiceWipes, 1);
    expect(await _rowCounts(db), {
      'draftReports': 0,
      'pendingTickets': 0,
      'pendingTicketAttachments': 0,
      'workSessions': 0,
      'cantierePunches': 0,
    });
    expect(prefs.getString('unrelated.pref'), isNull);
    expect(zoneResets, 1);
  });

  test('discardRetainedData wipes WITHOUT signing out (recovery screen)', () async {
    await ender().discardRetainedData();

    expect(auth.signOutCalls, 0, reason: 'the current session is not the one being discarded');
    expect(voiceWipes, 1);
    final counts = await _rowCounts(db);
    expect(counts.values.every((c) => c == 0), isTrue);
    expect(zoneResets, 1);
  });
}
