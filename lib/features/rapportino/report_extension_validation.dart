// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/extension_fields/extension_fields_api_client.dart'
    show
        ExtensionFieldDefinitionDto,
        decodeExtensionValues,
        extensionFieldDefinitionsFreshProvider;
import '../../domain/reports/extension_values.dart';
import '../../presentation/providers/report_editor_providers.dart'
    show draftReportRepositoryProvider;

/// Labels of the tenant's required "Altri campi" that this draft still leaves blank, kept live: it
/// re-emits when the technician edits a value and when the definitions change (the device's mirror
/// first, the live list a moment later). Empty when the tenant has no required fields — and also
/// when the definitions cannot be read at all, because the server re-checks on submit and a
/// device that cannot see the fields must not block a report it has no way to complete.
final reportMissingExtensionFieldsProvider = StreamProvider.autoDispose
    .family<List<String>, String>((ref, reportId) async* {
      final repo = ref.watch(draftReportRepositoryProvider);
      final List<ExtensionFieldDefinitionDto> definitions;
      try {
        definitions = await ref.watch(extensionFieldDefinitionsFreshProvider('report').future);
      } catch (_) {
        yield const [];
        return;
      }
      await for (final draft in repo.watchDraft(reportId)) {
        yield missingRequiredExtensionLabels(
          definitions,
          decodeExtensionValues(draft?.extensionValues),
        );
      }
    });
