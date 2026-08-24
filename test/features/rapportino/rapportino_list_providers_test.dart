// dart format width=100
// test/features/rapportino/rapportino_list_providers_test.dart
//
// Unit tests for the pure status-name resolver functions that drive the Rapportini list and
// RapportinoViewScreen — rapportinoStatusLabel / rapportinoIsSubmitted / rapportinoIsRejected.
//
// The gap these close (mobile audit item #1): the server-side rapportino lifecycle
// (Inviato/Controllato/Fatturato/Respinto/Annullato) now syncs back to the device
// (SyncService's `submittedReports` upsert), so these functions must read `stato` — not just the
// local `submissionState` this device itself set — to reflect a status change (in particular an
// office rejection) it never caused.

import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/rapportino/rapportino_list_providers.dart';

DraftReport _draft({
  String stato = 'Bozza',
  String submissionState = 'draft',
  bool isLocalOnly = true,
}) => DraftReport(
  id: 'r-1',
  tenantId: 'tenant-1',
  createdAt: DateTime.utc(2026, 6, 1),
  updatedAt: null,
  title: 'Rapportino',
  scheduleId: null,
  ticketId: null,
  customerId: null,
  details: null,
  metadataJson: null,
  insertedUserId: 'user-1',
  locationId: 'loc-1',
  startedAt: null,
  endedAt: null,
  documentTemplateId: null,
  customerSignatureAllegatoId: null,
  technicianSignatureAllegatoId: null,
  technicianNotes: null,
  closedAt: null,
  isAiAssisted: false,
  stato: stato,
  inviatoAt: null,
  controllatoAt: null,
  controllatoDa: null,
  fatturatoAt: null,
  materialiNotRequired: false,
  customerSignoffText: null,
  customerSignoffAt: null,
  isLocalOnly: isLocalOnly,
  submissionState: submissionState,
  idempotencyKey: null,
  submissionError: null,
);

void main() {
  group('rapportinoStatusLabel', () {
    test('Bozza, never touched → Bozza', () {
      expect(rapportinoStatusLabel(_draft()), 'Bozza');
    });

    test('uploadingMedia → Invio…, regardless of stato', () {
      expect(rapportinoStatusLabel(_draft(submissionState: 'uploadingMedia')), 'Invio…');
    });

    test('submitting → Invio…', () {
      expect(rapportinoStatusLabel(_draft(submissionState: 'submitting')), 'Invio…');
    });

    test('failed submit attempt → Bozza (stato never left Bozza on this device)', () {
      expect(rapportinoStatusLabel(_draft(submissionState: 'failed')), 'Bozza');
    });

    test('submitted locally, stato already Inviato (the realistic combination markSubmitted '
        'produces) → Inviata', () {
      expect(
        rapportinoStatusLabel(_draft(submissionState: 'submitted', stato: 'Inviato')),
        'Inviata',
      );
    });

    test('submitted locally, sync has not caught up to stato yet → still Inviata', () {
      // markSubmitted sets stato in the same write as submissionState in practice, but this
      // guards the moment a fixture (or a genuinely stale read) disagrees.
      expect(rapportinoStatusLabel(_draft(submissionState: 'submitted', stato: 'Bozza')), 'Inviata');
    });

    test('stato Inviato from a sync this device never itself submitted → Inviata', () {
      expect(rapportinoStatusLabel(_draft(submissionState: 'draft', stato: 'Inviato')), 'Inviata');
    });

    // ── The read-back this whole item exists for ──────────────────────────────
    test('stato Respinto (office rejection) → Respinta', () {
      expect(
        rapportinoStatusLabel(_draft(submissionState: 'submitted', stato: 'Respinto')),
        'Respinta',
      );
    });

    test('stato Controllato → Controllato', () {
      expect(
        rapportinoStatusLabel(_draft(submissionState: 'submitted', stato: 'Controllato')),
        'Controllato',
      );
    });

    test('stato Fatturato → Pagata', () {
      expect(
        rapportinoStatusLabel(_draft(submissionState: 'submitted', stato: 'Fatturato')),
        'Pagata',
      );
    });

    test('stato Annullato → Annullato', () {
      expect(
        rapportinoStatusLabel(_draft(submissionState: 'submitted', stato: 'Annullato')),
        'Annullato',
      );
    });
  });

  group('rapportinoIsSubmitted', () {
    test('false for an untouched local Bozza draft', () {
      expect(rapportinoIsSubmitted(_draft()), isFalse);
    });

    test('true once this device has submitted it', () {
      expect(rapportinoIsSubmitted(_draft(submissionState: 'submitted', stato: 'Inviato')), isTrue);
    });

    test('true for a Respinto report synced down, even if this device never submitted it', () {
      expect(rapportinoIsSubmitted(_draft(submissionState: 'draft', stato: 'Respinto')), isTrue);
    });
  });

  group('rapportinoIsRejected', () {
    test('true only for stato Respinto', () {
      expect(rapportinoIsRejected(_draft(stato: 'Respinto')), isTrue);
    });

    test('false for every other stato', () {
      for (final stato in ['Bozza', 'Inviato', 'Controllato', 'Fatturato', 'Annullato']) {
        expect(rapportinoIsRejected(_draft(stato: stato)), isFalse, reason: stato);
      }
    });
  });
}
