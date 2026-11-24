import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/branding/tenant_branding.dart';

class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.status, this.body);
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<void>? cancel) async =>
      ResponseBody.fromString(this.body, status, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });

  @override
  void close({bool force = false}) {}
}

Dio _dio(int status, String body) => Dio(BaseOptions(baseUrl: 'https://api.test'))
  ..httpClientAdapter = _FixedAdapter(status, body);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TenantBranding.fromJson', () {
    test('reads logo and company name and trims them', () {
      final b = TenantBranding.fromJson({'logoUrl': ' https://cdn.test/a.png ', 'companyName': ' Acme '});
      expect(b.logoUrl, 'https://cdn.test/a.png');
      expect(b.companyName, 'Acme');
    });

    test('treats blank and non-string values as absent', () {
      final b = TenantBranding.fromJson({'logoUrl': '  ', 'companyName': 5});
      expect(b.isEmpty, isTrue);
    });
  });

  group('TenantBranding.primaryColor', () {
    test('keeps the colour and trims it', () {
      final b = TenantBranding.fromJson({'logoUrl': 'x', 'primaryColor': ' #C03221 '});
      expect(b.primaryColor, '#C03221');
    });

    test('is null when absent, blank or not a string', () {
      expect(TenantBranding.fromJson({'logoUrl': 'x'}).primaryColor, isNull);
      expect(TenantBranding.fromJson({'primaryColor': '   '}).primaryColor, isNull);
      expect(TenantBranding.fromJson({'primaryColor': 5}).primaryColor, isNull);
    });

    test('toJson round trips', () {
      final b = TenantBranding.fromJson({'logoUrl': 'x', 'primaryColor': '#C03221'});
      expect(TenantBranding.fromJson(b.toJson()).primaryColor, '#C03221');
      expect(b.toJson()['primaryColor'], '#C03221');
    });

    test('a colour alone makes the branding non-empty', () {
      expect(const TenantBranding(primaryColor: '#C03221').isEmpty, isFalse);
    });
  });

  group('TenantBranding.isLoadableUrl', () {
    test('accepts absolute http and https URLs only', () {
      expect(TenantBranding.isLoadableUrl('https://cdn.test/a.png'), isTrue);
      expect(TenantBranding.isLoadableUrl('http://cdn.test/a.png'), isTrue);
      expect(TenantBranding.isLoadableUrl('/uploads/a.png'), isFalse);
      expect(TenantBranding.isLoadableUrl('javascript:alert(1)'), isFalse);
      expect(TenantBranding.isLoadableUrl('data:image/png;base64,AAAA'), isFalse);
      expect(TenantBranding.isLoadableUrl(null), isFalse);
    });
  });

  group('TenantBrandingRepository', () {
    test('fetch returns the server branding and caches it for the next cold start', () async {
      final repo = TenantBrandingRepository(
        _dio(200, '{"logoUrl":"https://cdn.test/a.png","companyName":"Acme"}'),
      );
      final fresh = await repo.fetch();
      expect(fresh?.companyName, 'Acme');

      final cached = await TenantBrandingRepository(_dio(500, '{}')).readCached();
      expect(cached?.logoUrl, 'https://cdn.test/a.png');
    });

    test('fetch degrades to null on a server error and keeps the previous cache', () async {
      await TenantBrandingRepository(_dio(200, '{"companyName":"Acme"}')).fetch();
      final failing = TenantBrandingRepository(_dio(500, '{"title":"boom"}'));
      expect(await failing.fetch(), isNull);
      expect((await failing.readCached())?.companyName, 'Acme');
    });

    test('readCached parses an old cache entry without a colour', () async {
      SharedPreferences.setMockInitialValues({
        'tenant_branding_v1': '{"logoUrl":null,"companyName":"Acme"}',
      });
      final cached = await TenantBrandingRepository(_dio(500, '{}')).readCached();
      expect(cached?.companyName, 'Acme');
      expect(cached?.primaryColor, isNull);
    });

    test('readCached is null when nothing was stored', () async {
      expect(await TenantBrandingRepository(_dio(200, '{}')).readCached(), isNull);
    });
  });
}
