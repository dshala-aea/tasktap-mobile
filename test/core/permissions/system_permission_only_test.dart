import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/features/timbra/cantiere_timbra_screen.dart'
    show requestGpsPermission;

/// Owner decision: the OS permission dialogs are the ONLY permission ask. No in-app
/// "we will ask you for X because Y" sheet precedes them.
class _FakeLocation extends ILocationService {
  _FakeLocation({required this.prompts});

  final bool prompts;
  int requests = 0;

  @override
  Future<GpsCoords?> getCurrentPosition() async => null;

  @override
  Future<bool> willPromptForPermission() async => prompts;

  @override
  Future<void> requestPermission() async => requests++;
}

Future<void> _pump(WidgetTester tester, _FakeLocation fake) async {
  await tester.pumpWidget(
    ProviderScope(retry: (_, _) => null, 
      overrides: [locationServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => requestGpsPermission(ref),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  group('requestGpsPermission', () {
    testWidgets('asks the system directly and shows no purpose sheet', (tester) async {
      final fake = _FakeLocation(prompts: true);
      await _pump(tester, fake);

      expect(fake.requests, 1);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Consenti la posizione'), findsNothing);
    });

    testWidgets('does not ask when the OS would not prompt (already decided)', (tester) async {
      final fake = _FakeLocation(prompts: false);
      await _pump(tester, fake);

      expect(fake.requests, 0);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  test('lib/ contains no custom permission purpose sheet', () {
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      expect(src.contains('askPermissionPurpose'), isFalse, reason: f.path);
      expect(src.contains('PermissionPurposeCard'), isFalse, reason: f.path);
    }
  });
}
