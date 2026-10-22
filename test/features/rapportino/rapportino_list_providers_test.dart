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
  bool submissionErrorTransient = false,
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
  richiedeSecondoIntervento: false,
  isLocalOnly: isLocalOnly,
  submissionState: submissionState,
  idempotencyKey: null,
  submissionError: null,
  submissionAttempts: 0,
  submissionErrorTransient: submissionErrorTransient,
  technicianSignaturePrefillSuppressed: false,
  strumentiPrefilled: false,
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

    test('failed submit attempt → Invio fallito, not Bozza (stato never left Bozza on this '
        'device, so nothing else would say the send did not go through)', () {
      expect(rapportinoStatusLabel(_draft(submissionState: 'failed')), kFailedSendStatusLabel);
      expect(rapportinoStatusLabel(_draft(submissionState: 'failed')), 'Invio fallito');
    });

    test('readyToSubmit → In attesa di invio, not Bozza — the technician pressed Invia and the '
        'row is waiting on the queue, not an untouched draft', () {
      expect(rapportinoStatusLabel(_draft(submissionState: 'readyToSubmit')), 'In attesa di invio');
    });

    test('a transient failed attempt is labelled the same — the list reports that the last '
        'send failed, not whether an unattended retry is still coming', () {
      expect(
        rapportinoStatusLabel(
          _draft(submissionState: 'failed', submissionErrorTransient: true),
        ),
        'Invio fallito',
      );
    });

    test('a failed local row whose server stato has moved on still reads the server status', () {
      // "Invio fallito" is this device's own stale local state; a lifecycle the office has since
      // moved further along outranks it, same as it does for the submitted fallback above.
      expect(rapportinoStatusLabel(_draft(submissionState: 'failed', stato: 'Inviato')), 'Inviata');
      expect(
        rapportinoStatusLabel(_draft(submissionState: 'failed', stato: 'Respinto')),
        'Respinta',
      );
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

  // Owner decision D8 (offline slice O-3 / audit F15): mobile edits Bozza only. Every other
  // state opens the read-only view. It is deliberately NOT the backend's own wider
  // ReportStateMachine.CanEditOrDelete window (Bozza/Inviato/Respinto): the editor's first
  // autosave rewrites `stato:'Bozza'` + `isLocalOnly:true`, which corrupts a synced report and
  // blinds sync to it forever. Reworking a Respinto goes through createReworkDraft instead.
  group('rapportinoOpensEditor', () {
    test('true for a Bozza that has not been sent from this device', () {
      for (final state in ['draft', 'readyToSubmit', 'failed']) {
        expect(
          rapportinoOpensEditor(_draft(submissionState: state)),
          isTrue,
          reason: 'a $state Bozza is still this device\'s working copy',
        );
      }
    });

    test('false for Inviato, Respinto, Controllato and Fatturato', () {
      for (final stato in ['Inviato', 'Respinto', 'Controllato', 'Fatturato']) {
        expect(rapportinoOpensEditor(_draft(stato: stato)), isFalse, reason: stato);
      }
    });

    test('false for a Bozza this device already submitted (stato lags the next sync)', () {
      expect(
        rapportinoOpensEditor(_draft(submissionState: 'submitted', stato: 'Bozza')),
        isFalse,
      );
    });

    test('false for Annullato and NonFatturabile', () {
      for (final stato in ['Annullato', 'NonFatturabile']) {
        expect(rapportinoOpensEditor(_draft(stato: stato)), isFalse, reason: stato);
      }
    });
  });

  group('rapportinoCanDelete', () {
    test('true for a Bozza', () {
      expect(rapportinoCanDelete(_draft()), isTrue);
    });

    test('false for every state past Bozza (the office Annulla workflow owns those)', () {
      for (final stato in ['Inviato', 'Respinto', 'Controllato', 'Fatturato', 'Annullato']) {
        expect(rapportinoCanDelete(_draft(stato: stato)), isFalse, reason: stato);
      }
    });

    test(
      'false mid-send — a delete there races markSubmitted and the row resurrects on the next sync',
      () {
        for (final state in ['uploadingMedia', 'submitting']) {
          expect(rapportinoCanDelete(_draft(submissionState: state)), isFalse, reason: state);
        }
      },
    );
  });

  group('totalOreMinutes', () {
    ReportStaffTableData row({
      double? hoursWorked,
      DateTime? startTime,
      DateTime? endTime,
      int pauseMinutes = 0,
    }) => ReportStaffTableData(
      id: 's-1',
      tenantId: 'tenant-1',
      createdAt: DateTime.utc(2026, 6, 1),
      reportId: 'r-1',
      userId: 'user-1',
      hoursWorked: hoursWorked,
      kmTraveled: 0.0,
      startTime: startTime,
      endTime: endTime,
      pauseMinutes: pauseMinutes,
    );

    test('sums hoursWorked in minutes when no timer was used', () {
      expect(totalOreMinutes([row(hoursWorked: 2.5)]), 150.0);
    });

    test('falls back to the startTime/endTime span minus pauses when hoursWorked is unset', () {
      final start = DateTime.utc(2026, 6, 21, 8, 0);
      final end = DateTime.utc(2026, 6, 21, 16, 0);
      expect(totalOreMinutes([row(startTime: start, endTime: end, pauseMinutes: 60)]), 420.0);
    });

    test(
      'prefers hoursWorked over the span once both are set — a stopped-then-restarted timer '
      'accumulates hoursWorked per segment, but the span also covers the idle gap in between',
      () {
        final start = DateTime.utc(2026, 6, 21, 8, 0);
        final end = DateTime.utc(2026, 6, 21, 16, 0); // 8h span, includes an idle gap
        final r = row(startTime: start, endTime: end, hoursWorked: 5.0); // 2 real segments
        expect(totalOreMinutes([r]), 300.0);
      },
    );

    test('sums across multiple staff rows', () {
      expect(
        totalOreMinutes([row(hoursWorked: 1.0), row(hoursWorked: 2.0)]),
        180.0,
      );
    });
  });
}
