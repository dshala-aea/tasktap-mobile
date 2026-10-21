// dart format width=100
// test/core/files/capture_store_test.dart
//
// Offline slice O-3 / audit F6 (P0-5): a pick must land in the app's own storage at pick time.
//
// The bug this closes: `image_picker`/`file_picker` return a path in the OS cache, the app
// persisted that path, and an OS cache purge turned a queued photo into a permanent
// "File non trovato" at submit — the one moment the technician can no longer re-take it.
//
// These tests use a real temp directory (no path_provider platform channel): `CaptureStore`'s
// constructor takes the directory, and `forApp()` is just a documents-dir + `captures/` join.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:tasktap_mobile/core/files/capture_store.dart';

void main() {
  late Directory root;
  late Directory sourceDir;
  late CaptureStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('capture_store_test_');
    sourceDir = Directory(p.join(root.path, 'temp_from_picker'));
    await sourceDir.create(recursive: true);
    // A store inside the temp root, exactly the shape `forApp()` builds under Documents.
    store = CaptureStore(Directory(p.join(root.path, 'docs', CaptureStore.folderName)));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> writeSource(String name, {int bytes = 8}) async {
    final file = File(p.join(sourceDir.path, name));
    await file.writeAsBytes(List<int>.filled(bytes, 7));
    return file;
  }

  group('CaptureStore.save', () {
    test('copies the file into captures/ and returns a path that is NOT the picker temp path', () async {
      final source = await writeSource('IMG_0001.jpg');

      final captured = await store.save(source.path, fileName: 'IMG_0001.jpg');

      expect(captured.path, isNot(source.path));
      expect(p.isWithin(store.directory.path, captured.path), isTrue);
      expect(await File(captured.path).exists(), isTrue);
      expect(p.basename(captured.path).endsWith('.jpg'), isTrue);
      // The original stays put — the copy is additive, the picker's temp file is never ours.
      expect(await source.exists(), isTrue);
    });

    test('the copy survives deleting the source (the whole point: an OS cache purge)', () async {
      final source = await writeSource('foto.png');

      final captured = await store.save(source.path, fileName: 'foto.png');
      await source.delete();

      expect(await File(captured.path).exists(), isTrue);
      expect(await File(captured.path).length(), 8);
    });

    test('returns the real size and keeps the user-facing name', () async {
      final source = await writeSource('rapportino.pdf', bytes: 1234);

      final captured = await store.save(source.path, fileName: 'rapportino.pdf');

      expect(captured.sizeBytes, 1234);
      expect(captured.fileName, 'rapportino.pdf');
    });

    test('derives the real content type from the extension, not a hard-coded image/jpeg', () async {
      final source = await writeSource('image_picker_file.png');

      final captured = await store.save(source.path, fileName: 'image_picker_file.png');

      expect(captured.contentType, 'image/png');
    });

    test('an explicit contentType wins over the extension (a re-encoded camera pick)', () async {
      final source = await writeSource('scaled_blob');

      final captured = await store.save(
        source.path,
        fileName: 'scaled_blob',
        contentType: 'image/jpeg',
      );

      expect(captured.contentType, 'image/jpeg');
    });

    test('an empty fileName falls back to the source basename', () async {
      final source = await writeSource('scansione.pdf');

      final captured = await store.save(source.path, fileName: '');

      expect(captured.fileName, 'scansione.pdf');
      expect(captured.contentType, 'application/pdf');
    });

    test('the stored file is always inside captures/, whatever the picker name', () async {
      final source = await writeSource('weird.exe.tmp');

      final captured = await store.save(source.path, fileName: 'weird.exe.tmp');

      // The stored name is rebuilt from a fresh uuid + a short alphanumeric extension, so a picker
      // name can never escape the captures directory.
      expect(p.isWithin(store.directory.path, captured.path), isTrue);
      expect(p.basename(captured.path).endsWith('.tmp'), isTrue);
    });

    test('a source path that does not exist throws — the caller must not queue it', () async {
      await expectLater(
        store.save(p.join(sourceDir.path, 'ghost.jpg'), fileName: 'ghost.jpg'),
        throwsA(isA<FileSystemException>()),
      );
      // And nothing partial was left behind for someone to upload.
      final leftovers = store.directory.existsSync()
          ? await store.directory.list().toList()
          : const <FileSystemEntity>[];
      expect(leftovers, isEmpty);
    });

    test('two picks of the same file get distinct durable paths', () async {
      final source = await writeSource('doppia.jpg');

      final first = await store.save(source.path, fileName: 'doppia.jpg');
      final second = await store.save(source.path, fileName: 'doppia.jpg');

      expect(first.path, isNot(second.path));
      expect(await File(first.path).exists(), isTrue);
      expect(await File(second.path).exists(), isTrue);
    });
  });

  group('contentTypeForFileName', () {
    test('maps every image/PDF extension the pickers can hand back', () {
      expect(contentTypeForFileName('a.jpg'), 'image/jpeg');
      expect(contentTypeForFileName('a.JPEG'), 'image/jpeg');
      expect(contentTypeForFileName('a.png'), 'image/png');
      expect(contentTypeForFileName('a.webp'), 'image/webp');
      expect(contentTypeForFileName('a.gif'), 'image/gif');
      expect(contentTypeForFileName('a.heic'), 'image/heic');
      expect(contentTypeForFileName('a.heif'), 'image/heic');
      expect(contentTypeForFileName('a.pdf'), 'application/pdf');
    });

    test('unknown and extensionless names use the caller fallback', () {
      expect(contentTypeForFileName('notes.txt'), 'application/octet-stream');
      expect(contentTypeForFileName('noextension'), 'application/octet-stream');
      expect(
        contentTypeForFileName('camera_blob', fallback: 'image/jpeg'),
        'image/jpeg',
        reason: 'the gallery picker re-encodes to JPEG, so an unnamed pick is still a JPEG',
      );
      expect(contentTypeForFileName('report.pdf', fallback: 'image/jpeg'), 'application/pdf');
    });
  });
}
