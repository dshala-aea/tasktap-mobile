// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// A recording not yet successfully uploaded. [idempotencyKey] is generated ONCE, when the
/// recording is saved, and reused on every retry so the server returns the same `audioRef`
/// instead of transcribing (and charging) twice.
class PendingRecording {
  const PendingRecording({
    required this.id,
    required this.file,
    required this.idempotencyKey,
    required this.createdAt,
    this.ticketId,
  });

  final String id;
  final File file;
  final String idempotencyKey;
  final DateTime createdAt;
  final String? ticketId;
}

/// File-based store: `<id>.m4a` plus `<id>.json` sidecar (`idempotencyKey`, `createdAt`,
/// `ticketId`) in one directory. Deliberately not Drift: a schema step would break the migration
/// fixtures and this data is a transient upload queue, not domain state.
class PendingRecordingStore {
  PendingRecordingStore(this.directory);

  /// The app documents directory (survives restarts, unlike the temp dir the recorder writes to).
  static Future<PendingRecordingStore> forApp() async {
    final docs = await getApplicationDocumentsDirectory();
    return PendingRecordingStore(Directory(p.join(docs.path, 'pending_voice')));
  }

  final Directory directory;

  /// Moves [recorded] into the store and writes its sidecar with a fresh key.
  Future<PendingRecording> add(File recorded, {String? ticketId}) async {
    await directory.create(recursive: true);
    final id = const Uuid().v4();
    final audio = File(p.join(directory.path, '$id.m4a'));
    try {
      await recorded.rename(audio.path);
    } on FileSystemException {
      await recorded.copy(audio.path); // rename fails across volumes
      await recorded.delete();
    }
    final pending = PendingRecording(
      id: id,
      file: audio,
      idempotencyKey: const Uuid().v4(),
      createdAt: DateTime.now().toUtc(),
      ticketId: ticketId,
    );
    await File(_sidecar(id)).writeAsString(
      jsonEncode({
        'idempotencyKey': pending.idempotencyKey,
        'createdAt': pending.createdAt.toIso8601String(),
        'ticketId': ticketId,
      }),
      flush: true,
    );
    return pending;
  }

  /// Oldest first. A sidecar without audio (or unreadable) is skipped, not fatal.
  Future<List<PendingRecording>> list() async {
    if (!await directory.exists()) return const [];
    final out = <PendingRecording>[];
    await for (final e in directory.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final id = p.basenameWithoutExtension(e.path);
      final audio = File(p.join(directory.path, '$id.m4a'));
      if (!await audio.exists()) continue;
      try {
        final map = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        out.add(
          PendingRecording(
            id: id,
            file: audio,
            idempotencyKey: map['idempotencyKey'] as String,
            createdAt: DateTime.parse(map['createdAt'] as String).toUtc(),
            ticketId: map['ticketId'] as String?,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  Future<void> delete(PendingRecording r) async {
    final sidecar = File(_sidecar(r.id));
    if (await r.file.exists()) await r.file.delete();
    if (await sidecar.exists()) await sidecar.delete();
  }

  String _sidecar(String id) => p.join(directory.path, '$id.json');
}
