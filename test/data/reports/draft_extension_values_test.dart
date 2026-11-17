// dart format width=100
// A rapportino draft is local until submit, so its "Altri campi" values live on the draft and the
// submit payload carries them (the server has no row to GET/PUT them against beforehand).
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';

class _MockApi extends Mock implements ReportSubmitApiClient {}

class _FakeRequest extends Fake implements SubmitReportRequest {}

const _id = 'rep-1';

void main() {
  setUpAll(() => registerFallbackValue(_FakeRequest()));

  late AppDatabase db;
  late DraftReportRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DraftReportRepository(db);
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _id,
            tenantId: 't',
            createdAt: DateTime.utc(2026, 1, 1),
            title: 'Rapportino',
            insertedUserId: 'u',
            locationId: 'loc',
            isLocalOnly: const Value(true),
            materialiNotRequired: const Value(true),
            submissionState: const Value('readyToSubmit'),
            idempotencyKey: const Value('k'),
          ),
        );
    await db
        .into(db.reportStaffTable)
        .insert(
          ReportStaffTableCompanion.insert(
            id: 's1',
            tenantId: 't',
            createdAt: DateTime.utc(2026, 1, 1),
            reportId: _id,
            userId: 'u',
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> define(
    String key, {
    String entityType = 'report',
    bool required = false,
    String? defaultValue,
    int sortOrder = 0,
  }) => db
      .into(db.extensionFieldDefinitions)
      .insert(
        ExtensionFieldDefinitionsCompanion.insert(
          id: '$entityType-$key',
          key: key,
          label: key,
          entityType: entityType,
          fieldType: 'text',
          isRequired: Value(required),
          defaultValue: Value(defaultValue),
          sortOrder: Value(sortOrder),
        ),
      );

  group('storing the values on the draft', () {
    test('a draft with nothing saved reads as empty', () async {
      expect(await repo.getExtensionValues(_id), isEmpty);
    });

    test('set / get round-trips and replaces the previous set', () async {
      await repo.setExtensionValues(_id, {'zona': 'Nord', 'lotto': '7'});
      expect(await repo.getExtensionValues(_id), {'zona': 'Nord', 'lotto': '7'});

      await repo.setExtensionValues(_id, {'zona': 'Sud'});
      expect(await repo.getExtensionValues(_id), {'zona': 'Sud'});
    });

    test('writing the values leaves the rest of the draft alone', () async {
      await repo.setExtensionValues(_id, {'zona': 'Nord'});

      final draft = (await repo.getDraft(_id))!;
      expect(draft.title, 'Rapportino');
      expect(draft.isLocalOnly, isTrue);
    });
  });

  group('buildSubmitExtensionValues', () {
    test('is null when the device knows no definition — the server must not be told "these are '
        'all the values"', () async {
      await repo.setExtensionValues(_id, {'zona': 'Nord'});

      expect(await repo.buildSubmitExtensionValues(_id), isNull);
    });

    test('other entity types\' definitions do not count', () async {
      await define('solo_ticket', entityType: 'ticket');

      expect(await repo.buildSubmitExtensionValues(_id), isNull);
    });

    test('carries the effective value of every report definition: stored, else default, else '
        'empty — and never a key without a definition', () async {
      await define('zona');
      await define('lotto', defaultValue: '1', sortOrder: 1);
      await define('note', sortOrder: 2);
      await repo.setExtensionValues(_id, {'zona': 'Nord', 'vecchio': 'x'});

      expect(await repo.buildSubmitExtensionValues(_id), {'zona': 'Nord', 'lotto': '1', 'note': ''});
    });
  });

  group('the submit request', () {
    test('includes the values typed in the wizard', () async {
      await define('zona');
      await repo.setExtensionValues(_id, {'zona': 'Nord'});
      final api = _MockApi();
      when(
        () => api.submitReport(
          request: any(named: 'request'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/reports/submit'),
          type: DioExceptionType.connectionError,
        ),
      );
      final queue = SubmissionQueue(
        repo: repo,
        apiClient: api,
        isOnline: () => true,
        recheckOnline: () async => true,
      );

      await queue.processAll(force: true);

      final sent =
          verify(
                () => api.submitReport(
                  request: captureAny(named: 'request'),
                  idempotencyKey: any(named: 'idempotencyKey'),
                ),
              ).captured.single
              as SubmitReportRequest;
      expect(sent.extensionValues, {'zona': 'Nord'});
      expect(sent.toJson()['extensionValues'], {'zona': 'Nord'});
    });

    test('omits the key entirely when the device knows no definition', () {
      const request = SubmitReportRequest(id: 'i', locationId: 'l', title: 't');

      expect(request.toJson().containsKey('extensionValues'), isFalse);
    });
  });
}
