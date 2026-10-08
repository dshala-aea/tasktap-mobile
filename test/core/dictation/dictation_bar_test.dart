// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/dictation/dictation_bar.dart';
import 'package:tasktap_mobile/core/dictation/dictation_capability.dart';
import 'package:tasktap_mobile/core/dictation/dictation_outcome.dart';
import 'package:tasktap_mobile/core/dictation/dictation_service.dart';
import 'package:tasktap_mobile/core/dictation/dictation_target.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

/// A dictation service the test drives by hand: it captures the two callbacks instead of emitting,
/// so a session can be ended at the moment the assertion is about.
class _FakeDictation implements IDictationService {
  _FakeDictation(this._capability);

  final DictationCapability _capability;
  int starts = 0;
  bool stopped = false;
  ValueChanged<String>? onTranscript;
  ValueChanged<DictationOutcome>? onDone;

  @override
  Future<DictationCapability> capability() async => _capability;

  @override
  bool get isListening => false;

  @override
  Future<void> start({
    required ValueChanged<String> onTranscript,
    required ValueChanged<DictationOutcome> onDone,
  }) async {
    starts++;
    this.onTranscript = onTranscript;
    this.onDone = onDone;
  }

  @override
  Future<void> stop() async => stopped = true;
}

const _ready = DictationCapability(
  recognizerAvailable: true,
  italianLocaleId: 'it_IT',
  onDeviceRecognitionAvailable: true,
  microphoneGranted: true,
);

DictationTarget _target(
  String id,
  String label,
  TextEditingController controller,
  ValueChanged<String> onChanged,
) => DictationTarget(id: id, label: label, controller: controller, onChanged: onChanged);

Future<void> _pump(
  WidgetTester tester,
  IDictationService service,
  DictationTargetRegistry registry,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dictationServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(body: DictationBar(registry: registry)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the bar names where it will write', () {
    testWidgets('a capable device offers a microphone, pointed at the default field', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final registry = DictationTargetRegistry()
        ..register(_target('details', 'Descrizione', controller, (_) {}));

      await _pump(tester, _FakeDictation(_ready), registry);

      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
      expect(find.text('Scrive in: Descrizione'), findsOneWidget);
    });

    testWidgets('selecting another field retargets the microphone and says so', (tester) async {
      final details = TextEditingController();
      final diagnosi = TextEditingController();
      addTearDown(details.dispose);
      addTearDown(diagnosi.dispose);
      final registry = DictationTargetRegistry()
        ..register(_target('details', 'Descrizione', details, (_) {}))
        ..register(_target('diagnosi', 'Diagnosi', diagnosi, (_) {}));

      await _pump(tester, _FakeDictation(_ready), registry);
      expect(find.text('Scrive in: Descrizione'), findsOneWidget);

      registry.select('diagnosi');
      await tester.pumpAndSettle();

      expect(find.text('Scrive in: Diagnosi'), findsOneWidget);
    });
  });

  group('an incapable device says why, permanently', () {
    testWidgets('the hint is on screen and tapping it never reaches the service', (tester) async {
      // The opposite of a reason-on-demand affordance: the one microphone in the step is dead, and
      // hiding the reason is the bug this bar exists to fix.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final registry = DictationTargetRegistry()
        ..register(_target('details', 'Descrizione', controller, (_) {}));
      final fake = _FakeDictation(const DictationCapability.unavailable());

      await _pump(tester, fake, registry);

      expect(find.byIcon(LucideIcons.mic), findsNothing);
      expect(find.byIcon(LucideIcons.micOff), findsOneWidget);
      expect(find.text('Questo dispositivo non ha il riconoscimento vocale.'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.micOff));
      await tester.pumpAndSettle();

      expect(fake.starts, 0);
    });
  });

  group('a session that went nowhere says so', () {
    testWidgets('a silent finish surfaces the notice instead of looking live', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final registry = DictationTargetRegistry()
        ..register(_target('details', 'Descrizione', controller, (_) {}));
      final fake = _FakeDictation(_ready);

      await _pump(tester, fake, registry);
      await tester.tap(find.byIcon(LucideIcons.mic));
      await tester.pumpAndSettle();
      expect(fake.starts, 1);

      fake.onDone!.call(DictationOutcome.heardNothing);
      await tester.pumpAndSettle();

      expect(find.textContaining('Non ho sentito nulla'), findsOneWidget);
    });
  });

  group('dictation appends to the field it was aimed at', () {
    testWidgets('speaking does not discard what was already typed', (tester) async {
      final controller = TextEditingController(text: 'Intervento urgente.');
      addTearDown(controller.dispose);
      String? reported;
      final registry = DictationTargetRegistry()
        ..register(_target('details', 'Descrizione', controller, (v) => reported = v));
      final fake = _FakeDictation(_ready);

      await _pump(tester, fake, registry);
      await tester.tap(find.byIcon(LucideIcons.mic));
      await tester.pumpAndSettle();

      fake.onTranscript!.call('sostituita la pompa');
      await tester.pumpAndSettle();

      expect(controller.text, 'Intervento urgente. sostituita la pompa');
      expect(
        reported,
        controller.text,
        reason: 'the editor state, not the controller, is what reaches the draft row',
      );
    });
  });
}
