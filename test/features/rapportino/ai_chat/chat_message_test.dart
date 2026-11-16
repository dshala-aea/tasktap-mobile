// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/chat_message.dart';

void main() {
  test('fromTurns keeps server order and marks voice turns', () {
    final turns = [
      AiConversationTurn(
        turnId: 't1',
        role: 'Operator',
        text: 'Ho sostituito la valvola',
        source: AiTurnSource.typed,
        at: DateTime.utc(2026, 11, 16, 9),
      ),
      const AiConversationTurn(
        turnId: 't2',
        role: 'Assistant',
        text: 'Quanti materiali?',
        source: AiTurnSource.typed,
      ),
      const AiConversationTurn(
        turnId: 't3',
        role: 'Operator',
        text: 'Nessuno',
        source: AiTurnSource.voice,
      ),
    ];

    final msgs = ChatMessage.fromTurns(turns);

    expect(msgs.map((m) => m.text), [
      'Ho sostituito la valvola',
      'Quanti materiali?',
      'Nessuno',
    ]);
    expect(msgs.map((m) => m.role), [ChatRole.operator, ChatRole.assistant, ChatRole.operator]);
    expect(msgs[2].source, ChatSource.voice);
    expect(msgs.first.at, DateTime.utc(2026, 11, 16, 9));
  });

  test('unknown roles render as the assistant', () {
    const turn = AiConversationTurn(
      turnId: 'x',
      role: 'ToolCall',
      text: '',
      source: AiTurnSource.typed,
    );
    expect(ChatMessage.fromTurns(const [turn]).single.role, ChatRole.assistant);
  });

  test('draft parses materialiNotRequired, default false', () {
    expect(AiCopilotDraftDto.fromJson(const {}).materialiNotRequired, isFalse);
    expect(
      AiCopilotDraftDto.fromJson(const {'materialiNotRequired': true}).materialiNotRequired,
      isTrue,
    );
  });
}
