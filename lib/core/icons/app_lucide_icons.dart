// Local replacement for `package:lucide_icons/lucide_icons.dart`.
//
// The published lucide_icons package (0.257.0, latest on pub.dev as of
// 2026-08) defines its icons via `class LucideIconData extends IconData`.
// Flutter's `IconData` is declared `final class IconData` in current stable
// SDKs, so that subclass no longer compiles ("The class 'IconData' can't be
// extended outside of its library because it's a final class."). There is no
// newer lucide_icons release that fixes this.
//
// `LucideIconData` adds no behaviour beyond forwarding to the `IconData`
// constructor with `fontFamily: 'Lucide', fontPackage: 'lucide_icons'`, so we
// reproduce just the handful of glyphs this app actually uses as plain
// `const IconData(...)` values instead of subclassing. The font asset itself
// still ships inside the `lucide_icons` package (declared in its own
// pubspec.yaml `fonts:` section), so `lucide_icons` stays a pubspec
// dependency — we only stop importing its broken Dart source.
//
// Code points copied verbatim from lucide_icons-0.257.0/lib/lucide_icons.dart.
library;

import 'package:flutter/widgets.dart';

class LucideIcons {
  const LucideIcons._();

  static const IconData alertCircle = IconData(
    0xf10b,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData alertTriangle = IconData(
    0xf10d,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData atSign = IconData(0xf170, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData bell = IconData(0xf19c, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData bellOff = IconData(
    0xf19f,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData briefcase = IconData(
    0xf1c9,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData calendar = IconData(
    0xf1d2,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData calendarCheck = IconData(
    0xf1d3,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData calendarDays = IconData(
    0xf1d6,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData calendarOff = IconData(
    0xf1d9,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData calendarPlus = IconData(
    0xf1da,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData calendarX = IconData(
    0xf1dd,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData camera = IconData(
    0xf1df,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData check = IconData(0xf1ee, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData checkCircle = IconData(
    0xf1f0,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData checkCircle2 = IconData(
    0xf1f1,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData chevronLeft = IconData(
    0xf1f9,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData chevronRight = IconData(
    0xf1fb,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData circle = IconData(
    0xf20b,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData circleDot = IconData(
    0xf20e,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData clipboardCheck = IconData(
    0xf219,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData clipboardList = IconData(
    0xf21c,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData clock = IconData(0xf221, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData cloud = IconData(0xf22e, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData cloudOff = IconData(
    0xf236,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData coffee = IconData(
    0xf243,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData download = IconData(
    0xf287,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData eye = IconData(0xf29c, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData eyeOff = IconData(
    0xf29d,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData fileEdit = IconData(
    0xf2b9,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData fileSignature = IconData(
    0xf2ce,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData fileText = IconData(
    0xf2d3,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData fileX = IconData(0xf2dc, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData filter = IconData(
    0xf2e0,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData fingerprint = IconData(
    0xf2e2,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData folderOpen = IconData(
    0xf30a,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData hardHat = IconData(
    0xf349,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData history = IconData(
    0xf35d,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData home = IconData(0xf35e, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData image = IconData(0xf365, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData imageOff = IconData(
    0xf367,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData inbox = IconData(0xf36a, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData link = IconData(0xf397, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData locateFixed = IconData(
    0xf3ac,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData logIn = IconData(0xf3af, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData logOut = IconData(
    0xf3b0,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData mail = IconData(0xf3b4, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData mapPin = IconData(
    0xf3c0,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData mapPinOff = IconData(
    0xf3c1,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData minus = IconData(0xf3dc, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData moon = IconData(0xf3eb, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData moreHorizontal = IconData(
    0xf3ed,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData moreVertical = IconData(
    0xf3ee,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData mic = IconData(
    0xf3d2,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );

  static const IconData micOff = IconData(
    0xf3d4,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );

  static const IconData package = IconData(
    0xf414,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData paperclip = IconData(
    0xf431,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData pencil = IconData(
    0xf43d,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData penTool = IconData(
    0xf43c,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData play = IconData(0xf457, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData plus = IconData(0xf45e, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData plusCircle = IconData(
    0xf45f,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData plusSquare = IconData(
    0xf460,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData receipt = IconData(
    0xf477,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData refreshCw = IconData(
    0xf480,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData search = IconData(
    0xf4ad,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );

  /// A search that matched nothing — distinct from [search], which invites one.
  static const IconData searchX = IconData(
    0xf4b1,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );

  /// Barcode/QR scan trigger, wherever the materiali catalog can be searched.
  static const IconData scanLine = IconData(
    0xf4a4,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );

  /// Stock in: a carico movement.
  static const IconData arrowDownToLine = IconData(
    0xf14b,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );

  /// Stock out: a scarico movement.
  static const IconData arrowUpFromLine = IconData(
    0xf162,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );

  /// Stock moved between warehouses: a trasferimento.
  static const IconData arrowLeftRight = IconData(
    0xf152,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData send = IconData(0xf4b2, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData settings = IconData(
    0xf4b9,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData shieldCheck = IconData(
    0xf4c1,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData square = IconData(
    0xf4f2,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData ticket = IconData(
    0xf539,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData timer = IconData(0xf53a, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData trash2 = IconData(
    0xf546,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData user = IconData(0xf564, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData userCheck = IconData(
    0xf566,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData userMinus = IconData(
    0xf56c,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData userPlus = IconData(
    0xf56e,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData users = IconData(0xf574, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData users2 = IconData(
    0xf575,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData warehouse = IconData(
    0xf58e,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData wifiOff = IconData(
    0xf597,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData wrench = IconData(
    0xf59d,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
  static const IconData x = IconData(0xf59e, fontFamily: 'Lucide', fontPackage: 'lucide_icons');
  static const IconData xCircle = IconData(
    0xf59f,
    fontFamily: 'Lucide',
    fontPackage: 'lucide_icons',
  );
}
