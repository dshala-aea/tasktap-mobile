import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/features/dashboard/id_plate_hero_comp.dart';

Widget _hero({String? logoUrl, String? companyName}) => MaterialApp(
  home: Scaffold(
    body: IdPlateHeroComp(
      userName: 'Mario Rossi',
      todayCount: 3,
      completedCount: 1,
      upcomingCount: 2,
      logoUrl: logoUrl,
      companyName: companyName,
    ),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('shows no logo when the tenant has none', (tester) async {
    await tester.pumpWidget(_hero());
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the tenant logo for an https URL', (tester) async {
    await tester.pumpWidget(_hero(logoUrl: 'https://cdn.test/a.png', companyName: 'Acme'));
    expect(find.byType(Image), findsOneWidget);
    expect(find.bySemanticsLabel('Acme'), findsOneWidget);
  });

  testWidgets('ignores a logo that is not an absolute http(s) URL', (tester) async {
    await tester.pumpWidget(_hero(logoUrl: '/uploads/a.png'));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('TenantLogo removes itself when the image fails to load', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TenantLogo(url: 'https://cdn.test/a.png', imageProvider: _FailingImage())),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsNothing);
  });
}

class _FailingImage extends ImageProvider<_FailingImage> {
  const _FailingImage();

  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_FailingImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.error(Exception('broken logo')));
}
