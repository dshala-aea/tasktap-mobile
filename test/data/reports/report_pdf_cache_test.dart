// dart format width=100
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/reports/report_pdf_cache.dart';

/// The PDF is the document a technician shows the customer on site, where there is no signal. These
/// tests pin the trade the cache makes: fresh online, present offline, never a blank document.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('tasktap_pdf_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ReportPdfCache cacheWith(Future<List<int>> Function(String) download) =>
      ReportPdfCache(download: download, rootLoader: () async => dir);

  test('online downloads and stores the PDF, and offline serves that same file', () async {
    var calls = 0;
    final cache = cacheWith((id) async {
      calls++;
      return [1, 2, 3];
    });

    final online = await cache.resolve('rep-1', online: true);
    expect(await online.readAsBytes(), [1, 2, 3]);
    expect(calls, 1);

    final offline = await cache.resolve('rep-1', online: false);
    expect(offline.path, online.path);
    expect(await offline.readAsBytes(), [1, 2, 3]);
    expect(calls, 1, reason: 'offline must not attempt a download');
  });

  test('every online open re-downloads, so the document is never a stale copy', () async {
    var version = 1;
    final cache = cacheWith((id) async => [version]);

    final first = await cache.resolve('rep-1', online: true);
    expect(await first.readAsBytes(), [1]);

    version = 2; // the report was edited and the server regenerated the PDF
    final second = await cache.resolve('rep-1', online: true);
    expect(second.path, first.path);
    expect(await second.readAsBytes(), [2]);
  });

  test('offline with nothing stored says so, and names the right reason', () async {
    final cache = cacheWith((id) async => fail('offline must not download'));

    await expectLater(
      cache.resolve('rep-1', online: false),
      throwsA(
        isA<ReportPdfUnavailable>().having(
          (e) => e.reason,
          'reason',
          ReportPdfFailure.notDownloaded,
        ),
      ),
    );
  });

  test('a failed online download falls back to the stored copy instead of failing', () async {
    var fail = false;
    final cache = cacheWith((id) async {
      if (fail) throw const SocketException('no route to host');
      return [9, 9];
    });
    await cache.resolve('rep-1', online: true);

    fail = true;
    final file = await cache.resolve('rep-1', online: true);
    expect(await file.readAsBytes(), [9, 9], reason: 'an older PDF beats no PDF on site');
  });

  test('a failed online download with nothing stored reports downloadFailed', () async {
    final cache = cacheWith((id) async => throw const SocketException('no route to host'));

    await expectLater(
      cache.resolve('rep-1', online: true),
      throwsA(
        isA<ReportPdfUnavailable>().having(
          (e) => e.reason,
          'reason',
          ReportPdfFailure.downloadFailed,
        ),
      ),
    );
  });

  test('an empty body is a failure, and leaves no zero-byte file behind', () async {
    final cache = cacheWith((id) async => const <int>[]);

    await expectLater(
      cache.resolve('rep-1', online: true),
      throwsA(
        isA<ReportPdfUnavailable>().having(
          (e) => e.reason,
          'reason',
          ReportPdfFailure.downloadFailed,
        ),
      ),
    );
    expect(await cache.cached('rep-1'), isNull);
  });

  test('a zero-byte file left by a killed write is treated as absent and removed', () async {
    final pdfs = Directory('${dir.path}/report_pdfs')..createSync(recursive: true);
    final stale = File('${pdfs.path}/report-rep-1.pdf')..writeAsBytesSync(const []);
    expect(stale.existsSync(), isTrue);

    final cache = cacheWith((id) async => fail('offline must not download'));

    expect(await cache.cached('rep-1'), isNull);
    expect(stale.existsSync(), isFalse, reason: 'a truncated PDF would open as a blank page');
  });

  test("one report never reads another report's PDF", () async {
    final cache = cacheWith((id) async => id == 'a' ? [1] : [2]);

    await cache.resolve('a', online: true);
    await cache.resolve('b', online: true);

    expect(await (await cache.resolve('a', online: false)).readAsBytes(), [1]);
    expect(await (await cache.resolve('b', online: false)).readAsBytes(), [2]);
  });
}
