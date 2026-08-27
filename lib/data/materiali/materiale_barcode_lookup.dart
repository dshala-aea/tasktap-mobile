// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/scanner/barcode_scan_sheet.dart';
import '../local/app_database.dart';
import '../sync/connectivity_provider.dart';
import '../sync/sync_service.dart' show appDatabaseProvider;
import '../api/dio_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// MaterialeMatch — the minimum a caller needs to show or select a scanned material
//
// Deliberately not a Materiale/MaterialiData row: a local-mirror hit and a live-lookup hit come
// back in different shapes (a Drift data class vs. raw JSON), and every call site so far
// (rapportino Materiali step, magazzino stock browse, admin catalog list) only needs id/code/name/
// unit — not the full catalog row. Widening this later is cheap; narrowing a leaked entity type
// back down after three call sites depend on its exact shape is not.
// ══════════════════════════════════════════════════════════════════════════════

class MaterialeMatch {
  const MaterialeMatch({required this.id, required this.code, required this.name, this.unitOfMeasure});

  final String id;
  final String code;
  final String name;
  final String? unitOfMeasure;

  factory MaterialeMatch.fromLocal(MaterialiData m) =>
      MaterialeMatch(id: m.id, code: m.code, name: m.name, unitOfMeasure: m.unitOfMeasure);

  /// Shape matches the backend's `MaterialeWithBarcodesDto` (GET /api/materiali/lookup).
  factory MaterialeMatch.fromLookupJson(Map<String, dynamic> j) => MaterialeMatch(
    id: j['id'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
    unitOfMeasure: j['unitOfMeasure'] as String?,
  );
}

/// Matches a scanned barcode against the local mirror first (works offline, and is what a synced
/// device should hit almost every time), then — only when nothing local matched and the device is
/// online — against the live lookup endpoint, for a barcode added to the catalog since the last
/// sync. Returns null when neither finds anything; the caller decides how to tell the technician
/// (e.g. offering the raw scanned code as free text, same as typing one manually).
Future<MaterialeMatch?> lookupMaterialeByBarcode(WidgetRef ref, String barcode) async {
  final db = ref.read(appDatabaseProvider);

  final localHit = await (db.select(db.materialeBarcodes)
        ..where((b) => b.barcode.equals(barcode)))
      .getSingleOrNull();
  if (localHit != null) {
    final materiale = await (db.select(db.materiali)
          ..where((m) => m.id.equals(localHit.materialeId)))
        .getSingleOrNull();
    if (materiale != null) return MaterialeMatch.fromLocal(materiale);
    // The barcode row exists but its parent doesn't (e.g. the material went inactive and dropped
    // out of sync after the barcode itself was cached) — fall through to a live lookup rather
    // than reporting a match for a material the device can no longer actually show.
  }

  if (!ref.read(isOnlineProvider)) return null;

  final dio = ref.read(dioProvider);
  try {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/materiali/lookup',
      queryParameters: {'barcode': barcode},
    );
    final data = response.data;
    if (data == null) return null;
    return MaterialeMatch.fromLookupJson(data);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
}

/// Opens the camera scan sheet, then resolves whatever it captured to a material. Returns null
/// when the technician backs out of the scanner without a result, or nothing matched.
Future<MaterialeMatch?> scanForMateriale(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Scansiona materiale',
}) async {
  final code = await openBarcodeScanSheet(context, title: title);
  if (code == null) return null;
  if (!context.mounted) return null;
  return lookupMaterialeByBarcode(ref, code);
}
