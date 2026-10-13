// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

/// The maintenance-template DTO is hand-written, so nothing but a test proves its `fromJson` reads
/// the keys the server actually sends. `sync_inbound_contract_test.dart` pins those keys against the
/// snapshot; this file pins the parsing behaviour itself — the shapes the snapshot cannot express
/// (int32-as-string, a null `latestPublishedVersion`) and the round trip through `toJson`.
void main() {
  Map<String, dynamic> json({
    Object? origin = 'System',
    Object? latestPublishedVersion = 2,
    Object? isActive = true,
    Object? description,
  }) => {
    'id': 'tpl-1',
    'origin': origin,
    'name': 'Manutenzione caldaia',
    'description': description,
    'isActive': isActive,
    'latestPublishedVersion': latestPublishedVersion,
  };

  test('parses a full template', () {
    final t = SyncMaintenanceTemplateDto.fromJson(
      json(origin: 'Tenant', description: 'Annuale', latestPublishedVersion: 4),
    );
    expect(t.id, 'tpl-1');
    expect(t.origin, 'Tenant');
    expect(t.name, 'Manutenzione caldaia');
    expect(t.description, 'Annuale');
    expect(t.isActive, isTrue);
    expect(t.latestPublishedVersion, 4);
  });

  test('a template with no published version and no description', () {
    final t = SyncMaintenanceTemplateDto.fromJson(
      json(latestPublishedVersion: null, description: null),
    );
    expect(t.latestPublishedVersion, isNull);
    expect(t.description, isNull);
  });

  test('an int32 that arrives as a string still parses', () {
    final t = SyncMaintenanceTemplateDto.fromJson(json(latestPublishedVersion: '3'));
    expect(t.latestPublishedVersion, 3);
  });

  test('isActive defaults to true when the server omits it', () {
    final t = SyncMaintenanceTemplateDto.fromJson(json(isActive: null));
    expect(t.isActive, isTrue);
  });

  test('toJson round-trips through fromJson unchanged', () {
    final original = SyncMaintenanceTemplateDto.fromJson(
      json(origin: 'Tenant', description: 'Annuale', latestPublishedVersion: 7),
    );
    final again = SyncMaintenanceTemplateDto.fromJson(original.toJson());
    expect(again.id, original.id);
    expect(again.origin, original.origin);
    expect(again.name, original.name);
    expect(again.description, original.description);
    expect(again.isActive, original.isActive);
    expect(again.latestPublishedVersion, original.latestPublishedVersion);
  });

  test('the sync result carries the member, and distinguishes an older backend', () {
    final full = SyncResultDto.fromJson({
      'syncedAt': '2026-10-08T08:00:00Z',
      'since': null,
      'maintenanceTemplates': [json()],
    });
    expect(full.carriesMaintenanceTemplates, isTrue);
    expect(full.maintenanceTemplates, hasLength(1));
    expect(SyncResultDto.referenceWireKeys, contains('maintenanceTemplates'));

    final older = SyncResultDto.fromJson({
      'syncedAt': '2026-10-08T08:00:00Z',
      'since': null,
    });
    expect(
      older.carriesMaintenanceTemplates,
      isFalse,
      reason: 'an older backend must NOT look like "every template was deleted"',
    );
    expect(older.maintenanceTemplates, isEmpty);
  });
}
