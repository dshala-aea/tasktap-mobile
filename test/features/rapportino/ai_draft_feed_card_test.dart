// dart format width=100
// The editor card of a rapportino fed by a live AI draft (Task 12, fix round 1): what cannot reach
// the server is shown PERSISTENTLY on the card, never only as a passing toast.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/rapportino/ai_draft_feed.dart';
import 'package:tasktap_mobile/features/rapportino/ai_draft_feed_card.dart';

class _OfflineAi extends AiApiClient {
  _OfflineAi() : super(Dio());
  @override
  Future<AiQuotaDto> getQuota() async => const AiQuotaDto(monthlyLimit: 1, used: 0, remaining: 1);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the blocked state and the unsendable edits are shown on the card', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'rep-1',
              tenantId: 't',
              createdAt: DateTime.utc(2026, 10, 20),
              title: 'R',
              insertedUserId: 'u',
              locationId: 'l',
            ),
          );
      await db
          .into(db.reportMateriali)
          .insert(
            ReportMaterialiCompanion.insert(
              id: 'm',
              tenantId: 't',
              createdAt: DateTime.utc(2026, 10, 20),
              reportId: 'rep-1',
              freeTextName: const Value('--'),
              quantity: 1,
            ),
          );
      final store = AiDraftFeedStore();
      await store.link(sessionId: 'sess-1', reportId: 'rep-1');
      final state = (await store.load('sess-1'))!..blocked = true;
      await store.save(state);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          aiApiClientProvider.overrideWithValue(_OfflineAi()),
        ],
        child: const MaterialApp(home: Scaffold(body: AiDraftFeedCard(reportId: 'rep-1'))),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(find.textContaining('limite'), findsOneWidget, reason: 'blocked, shown persistently');
    expect(find.textContaining('non sincronizzabil'), findsOneWidget);
    expect(find.textContaining('--'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 1));
  });
}
