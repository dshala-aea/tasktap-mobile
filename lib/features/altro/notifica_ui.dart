import 'package:flutter/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Notification presentation
//
// One mapping from a notification's `tipo` (the wire NotificationTypeEnum name) to its icon and
// Italian label, shared by the list row and the detail page so the two cannot drift. The icons
// deliberately cover only the types with an unambiguous, already-established symbol elsewhere in
// the app; everything else gets the generic bell.
// ══════════════════════════════════════════════════════════════════════════════

IconData notificaIcon(String? tipo) {
  return switch (tipo) {
    'TicketAssigned' || 'TicketCreated' => LucideIcons.ticket,
    'TicketStatusChanged' || 'TicketCompleted' => LucideIcons.clipboardCheck,
    'TicketOverdue' || 'TicketOverdueDigest' => LucideIcons.alertTriangle,
    'ScheduleReminder' || 'ScheduleStarting' => LucideIcons.calendar,
    'WorkLogSubmitted' => LucideIcons.fileText,
    'ReportReviewed' => LucideIcons.clipboardCheck,
    'ReportRejected' => LucideIcons.fileX,
    'ReportCancelled' => LucideIcons.calendarX,
    'AbsenceRequestSubmitted' ||
    'AbsenceRequestDecided' => LucideIcons.calendarCheck,
    'CantiereAssigned' => LucideIcons.hardHat,
    'SeatLimitAlert' => LucideIcons.alertTriangle,
    // lucide_icons ^0.257.0 has no clockAlert; pencil reads as "edited".
    'WorkLogCorrected' => LucideIcons.pencil,
    _ => LucideIcons.bell,
  };
}

/// Human label for a notification type, mirroring the web portal's
/// `notifiche.tipi` localisation. Null when the type is unknown to this build —
/// the page then shows the icon alone rather than a raw enum name.
String? notificaEtichettaTipo(String? tipo) {
  return switch (tipo) {
    'TicketAssigned' => 'Ticket assegnati',
    'TicketStatusChanged' => 'Cambi di stato dei ticket',
    'TicketCreated' => 'Nuovi ticket',
    'TicketCompleted' => 'Ticket completati',
    'TicketOverdue' => 'Ticket in ritardo',
    'TicketOverdueDigest' => 'Riepilogo ticket in ritardo',
    'ScheduleReminder' => 'Promemoria pianificazione',
    'ScheduleStarting' => 'Pianificazioni in partenza',
    'ScheduleChanged' => 'Modifiche pianificazioni',
    'LicenseExpiring' => 'Licenza in scadenza',
    'LicenseExpired' => 'Licenza scaduta',
    'WorkLogSubmitted' => 'Ore e presenze inviate',
    'WorkLogCorrected' => "Ore corrette dall'ufficio",
    'DocumentUploaded' => 'Documenti caricati',
    'SystemAnnouncement' => 'Comunicazioni di sistema',
    'UserMention' => 'Menzioni',
    'LowStock' => 'Scorte in esaurimento',
    'AbsenceRequestDecided' => 'Esito delle richieste di assenza',
    'AbsenceRequestSubmitted' => 'Richieste di assenza',
    'MaintenanceDue' => 'Manutenzioni in scadenza',
    'OvertimeThresholdCrossed' => 'Soglia straordinari superata',
    'ReportSubmitted' => "Rapporti di lavoro inviati all'ufficio",
    'ReportReviewed' => 'Rapporti di lavoro controllati',
    'ReportRejected' => 'Rapporti di lavoro respinti',
    'ReportCancelled' => 'Rapporti di lavoro annullati',
    'CantiereAssigned' => 'Assegnazioni cantiere',
    'SeatLimitAlert' => 'Limite posti',
    _ => null,
  };
}
