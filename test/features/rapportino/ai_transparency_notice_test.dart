// test/features/rapportino/ai_transparency_notice_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/rapportino/ai_transparency_notice.dart';

void main() {
  testWidgets('states that the assistant is AI and audio is sent for transcription', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiTransparencyNotice())),
    );

    expect(find.text(AiTransparencyNotice.text), findsOneWidget);
    expect(AiTransparencyNotice.text, contains('assistente AI'));
    expect(AiTransparencyNotice.text, contains('trascrizione'));
  });
}
