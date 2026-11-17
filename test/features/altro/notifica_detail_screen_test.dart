// test/features/altro/notifica_detail_screen_test.dart
//
// The detail page exists for the notifications that have nothing to open: their body used to be
// clipped in the list and the tap did nothing. The page loads by id alone, so these tests never
// seed the list and never depend on list state.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/altro/notifica_detail_screen.dart';
import 'package:tasktap_mobile/features/altro/notifiche_provider.dart';

/// Records the read receipt the page sends, without touching the network.
class _RecordingNotifier extends NotificheNotifier {
  _RecordingNotifier(super.db, super.dio, super.ref);

  final List<String> markedRead = [];

  @override
  Future<void> segnaLetta(String id) async => markedRead.add(id);
}

/// Simulates the receipt failing — the page must still show the text.
class _FailingNotifier extends NotificheNotifier {
  _FailingNotifier(super.db, super.dio, super.ref);

  @override
  Future<void> segnaLetta(String id) async => throw Exception('offline');
}

AppNotifica _notifica({
  String id = 'n1',
  bool letta = false,
  String corpo = 'Comunicazione di servizio.',
}) => AppNotifica(
  id: id,
  titolo: 'Comunicazione',
  corpo: corpo,
  timestamp: DateTime.utc(2026, 10, 31, 9, 30),
  letta: letta,
  tipo: 'SystemAnnouncement',
);

/// Builds the page with the by-id provider overridden by [load] and the
/// notifications notifier replaced by [notifier] (default: a recorder), over an
/// in-memory DB.
/// Builds the page with the by-id provider overridden by [load] and the
/// notifications notifier replaced by [notifier] (default: a recorder), over an
/// in-memory DB. The container is exposed so a test can read the notifier even
/// when the page never asks for it (the already-read case).
({Widget widget, ProviderContainer container}) _build({
  required Future<AppNotifica> Function() load,
  NotificheNotifier Function(AppDatabase, Ref)? notifier,
}) {
  final db = AppDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      notificaDettaglioProvider.overrideWith((ref, id) => load()),
      notificheProvider.overrideWith((ref) {
        return notifier?.call(db, ref) ?? _RecordingNotifier(db, Dio(), ref);
      }),
    ],
  );
  addTearDown(container.dispose);
  // Construct it up front so the test can read it regardless of whether the
  // page needed a receipt.
  container.read(notificheProvider.notifier);
  return (
    widget: UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotificaDetailScreen(id: 'n1')),
    ),
    container: container,
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // main.dart initialises this at startup; the page's Italian date format needs it.
    await initializeDateFormatting('it', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'internal_user_id': 'test-user'});
  });

  testWidgets('renders the full body without a line limit', (tester) async {
    final longBody = List.filled(
      30,
      'Questa è una comunicazione lunga che deve essere leggibile per intero.',
    ).join('\n\n');

    await tester.pumpWidget(
      _build(load: () async => _notifica(corpo: longBody)).widget,
    );
    await tester.pumpAndSettle();

    expect(find.text(longBody), findsOneWidget);
    final body = tester.widget<Text>(find.text(longBody));
    expect(body.maxLines, isNull);
    expect(body.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('an unknown id shows "Notifica non disponibile"', (tester) async {
    await tester.pumpWidget(
      _build(load: () async => throw const NotificaNonDisponibile()).widget,
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifica non disponibile'), findsOneWidget);
  });

  testWidgets('a transport failure shows Retry and retries', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _build(
        load: () async {
          calls++;
          if (calls == 1) {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/notifications/n1'),
              type: DioExceptionType.connectionError,
            );
          }
          return _notifica();
        },
      ).widget,
    );
    await tester.pumpAndSettle();

    expect(find.text('Riprova'), findsOneWidget);

    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.text('Comunicazione di servizio.'), findsOneWidget);
  });

  testWidgets('an unread notification is marked read on open, once', (
    tester,
  ) async {
    final built = _build(load: () async => _notifica(letta: false));
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    final recorder =
        built.container.read(notificheProvider.notifier) as _RecordingNotifier;
    expect(recorder.markedRead, ['n1']);
  });

  testWidgets('an already-read notification is not marked again', (
    tester,
  ) async {
    final built = _build(load: () async => _notifica(letta: true));
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    final recorder =
        built.container.read(notificheProvider.notifier) as _RecordingNotifier;
    expect(recorder.markedRead, isEmpty);
  });

  testWidgets('a failed mark-read still renders the body', (tester) async {
    final built = _build(
      load: () async => _notifica(letta: false),
      notifier: (db, ref) => _FailingNotifier(db, Dio(), ref),
    );
    await tester.pumpWidget(built.widget);
    await tester.pumpAndSettle();

    expect(find.text('Comunicazione di servizio.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
