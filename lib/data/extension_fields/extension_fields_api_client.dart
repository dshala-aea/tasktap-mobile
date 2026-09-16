// dart format width=100
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../sync/connectivity_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ExtensionFieldsApiClient
//
// Thin Dio wrapper for `ExtensionFieldsController` (backend, TaskTapAPI.Api) — tenant-defined
// custom fields on an entity. Two endpoints only, both live-fetched with no local Drift mirror
// (same "fetch-on-demand" shape as TicketDetailApiClient's own tabs, see that file's header
// comment): the field *definitions* an admin configured for an entity type, and the *values* one
// specific entity currently holds for them.
//
// `entityType` here is always the backend's own lowercase key ('ticket', 'cantiere', 'report',
// 'cantiereworklog', …) — see ExtensionFieldsController.DispatchGetAsync/DispatchSetAsync for the
// exact dispatch table this must match.
// ══════════════════════════════════════════════════════════════════════════════

class ExtensionFieldsApiClient {
  ExtensionFieldsApiClient(this._dio);

  final Dio _dio;

  /// Active field definitions configured for [entityType], in the order the office arranged them.
  ///
  /// `pageSize: 100` (the endpoint's own clamp ceiling — see `ListQuery.SafePageSize`): a tenant's
  /// per-entity-type field count is realistically a handful, so one page always covers it; there
  /// is nothing here worth paginating through.
  Future<List<ExtensionFieldDefinitionDto>> fetchDefinitions(String entityType) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/extension-fields/definitions',
      queryParameters: {'entityType': entityType, 'pageSize': 100},
    );
    final items = (response.data?['items'] as List<dynamic>?) ?? const [];
    return items.cast<Map<String, dynamic>>().map(ExtensionFieldDefinitionDto.fromJson).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// [entityId]'s current values as a flat key→string map — only keys with something saved are
  /// present; a definition with nothing recorded for this entity simply has no key here.
  Future<Map<String, String>> fetchValues(String entityType, String entityId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/extension-fields/$entityType/$entityId/values',
    );
    final data = response.data ?? const {};
    return data.map((key, value) => MapEntry(key, value?.toString() ?? ''));
  }

  /// Writes [values] onto [entityId]. The endpoint merges into whatever is already stored and
  /// silently drops any key that isn't a currently-active definition for this entity type (see
  /// `ExtensionValueService.SetValuesAsync`) — so this can always send the section's full working
  /// set without first re-checking which keys still apply.
  Future<void> saveValues(String entityType, String entityId, Map<String, String> values) async {
    await _dio.put<void>('/api/extension-fields/$entityType/$entityId/values', data: values);
  }
}

final extensionFieldsApiClientProvider = Provider<ExtensionFieldsApiClient>((ref) {
  return ExtensionFieldsApiClient(ref.watch(dioProvider));
});

// ══════════════════════════════════════════════════════════════════════════════
// Offline signal — same shape as TicketDetailOfflineException: thrown before a request is even
// attempted, so the section can say "needs a connection" instead of a generic/ambiguous failure.
// ══════════════════════════════════════════════════════════════════════════════

class ExtensionFieldsOfflineException implements Exception {
  const ExtensionFieldsOfflineException();

  @override
  String toString() => 'Offline: campi aggiuntivi non disponibili senza connessione.';
}

// ══════════════════════════════════════════════════════════════════════════════
// Providers
// ══════════════════════════════════════════════════════════════════════════════

/// Active field definitions for one backend entity-type key, e.g. `'ticket'`.
final extensionFieldDefinitionsProvider = FutureProvider.autoDispose
    .family<List<ExtensionFieldDefinitionDto>, String>((ref, entityType) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const ExtensionFieldsOfflineException();
      }
      final api = ref.watch(extensionFieldsApiClientProvider);
      return api.fetchDefinitions(entityType);
    });

/// One entity's current extension-field values, keyed by `(entityType, entityId)` so a ticket and
/// a cantiere sharing no relation never collide, and so switching which entity a screen is showing
/// (e.g. picking a different cantiere) naturally invalidates to a fresh fetch.
final extensionFieldValuesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, (String entityType, String entityId)>((ref, key) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const ExtensionFieldsOfflineException();
      }
      final api = ref.watch(extensionFieldsApiClientProvider);
      return api.fetchValues(key.$1, key.$2);
    });

// ══════════════════════════════════════════════════════════════════════════════
// DTOs
// ══════════════════════════════════════════════════════════════════════════════

/// How an [ExtensionFieldDefinitionDto.fieldType] renders and what shape its stored string value
/// takes. `fieldType` itself is a free string an admin picked when configuring the field (backend
/// stores whatever was sent, no enum) — [ExtensionFieldRenderType.of] maps the values in current
/// use and falls back to [text] for anything else, matching every other free-string-from-the-
/// backend switch in this app (see e.g. `_controlTypeFromWire`'s own `unknown` fallback).
enum ExtensionFieldRenderType {
  text,
  number,
  date,
  boolean,
  select;

  static ExtensionFieldRenderType of(String fieldType) {
    return switch (fieldType.trim().toLowerCase()) {
      'number' => ExtensionFieldRenderType.number,
      'date' => ExtensionFieldRenderType.date,
      'boolean' => ExtensionFieldRenderType.boolean,
      'select' => ExtensionFieldRenderType.select,
      _ => ExtensionFieldRenderType.text,
    };
  }
}

/// One tenant-configured custom field — mirrors `ExtensionFieldDefinition` (backend,
/// TaskTapAPI.Core.Entities).
class ExtensionFieldDefinitionDto {
  const ExtensionFieldDefinitionDto({
    required this.id,
    required this.key,
    required this.label,
    required this.entityType,
    required this.fieldType,
    required this.isRequired,
    required this.showInCard,
    required this.sortOrder,
    this.options,
    this.unit,
    this.defaultValue,
    this.placeholder,
  });

  final String id;
  final String key;
  final String label;
  final String entityType;
  final String fieldType;
  final bool isRequired;
  final bool showInCard;
  final int sortOrder;

  /// A choice list for [ExtensionFieldRenderType.select] — see [choiceOptions] for the parsed
  /// form. Free text on the backend with no enforced shape; unrelated to every other field type.
  final String? options;
  final String? unit;
  final String? defaultValue;
  final String? placeholder;

  ExtensionFieldRenderType get renderType => ExtensionFieldRenderType.of(fieldType);

  /// [options] parsed as a choice list. Tries a JSON array of strings first — the shape
  /// `TicketControlDto.choiceOptions` already uses for the same "Options" idea on a checklist
  /// control — and falls back to a plain comma-separated split, since this field has no format
  /// enforced server-side and an admin may simply have typed `Rosso, Verde, Blu`. Empty/unparsable
  /// input yields no choices rather than throwing.
  List<String> get choiceOptions {
    final raw = options;
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {
      // Not JSON — fall through to the comma-separated reading below.
    }
    return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  factory ExtensionFieldDefinitionDto.fromJson(Map<String, dynamic> json) {
    return ExtensionFieldDefinitionDto(
      id: json['id'] as String? ?? '',
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      entityType: json['entityType'] as String? ?? '',
      fieldType: json['fieldType'] as String? ?? 'text',
      isRequired: json['isRequired'] as bool? ?? false,
      showInCard: json['showInCard'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
      options: json['options'] as String?,
      unit: json['unit'] as String?,
      defaultValue: json['defaultValue'] as String?,
      placeholder: json['placeholder'] as String?,
    );
  }
}
