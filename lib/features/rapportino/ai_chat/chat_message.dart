// dart format width=100
import '../../../data/ai/ai_api_client.dart';

/// Who said it. Mirrors the server's `AiConversationTurn.role` (`Operator` / `Assistant`).
enum ChatRole { operator, assistant }

/// How the operator's words reached the server. Voice turns carry the recording as the model's
/// input (ADR-0023) and a transcript for display.
enum ChatSource { typed, voice }

/// One bubble in the Descrivi chat.
///
/// The thread is a projection of the conversation the server already stores
/// (`GET /api/ai/conversations/{id}` returns every operator/assistant turn), plus the optimistic
/// operator message the screen shows while a turn is in flight.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.source = ChatSource.typed,
    this.at,
  });

  final String id;
  final ChatRole role;
  final String text;
  final ChatSource source;
  final DateTime? at;

  /// Server order, oldest first. A role other than `Operator` renders as the assistant.
  static List<ChatMessage> fromTurns(List<AiConversationTurn> turns) => [
    for (final t in turns)
      ChatMessage(
        id: t.turnId,
        role: t.isOperator ? ChatRole.operator : ChatRole.assistant,
        text: t.text,
        source: t.source == AiTurnSource.voice ? ChatSource.voice : ChatSource.typed,
        at: t.at,
      ),
  ];

  /// The optimistic bubble for a recording that is still uploading: the server has not seen it yet,
  /// so there is no transcript to show.
  static ChatMessage operatorVoice({required String id, DateTime? at}) => ChatMessage(
    id: id,
    role: ChatRole.operator,
    text: 'Messaggio vocale',
    source: ChatSource.voice,
    at: at,
  );
}
