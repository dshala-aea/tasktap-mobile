// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Table definitions — mirror the backend sync DTO fields exactly.
// Base fields (id, tenant_id, created_at, updated_at) are replicated on every
// table; no EF navigation properties are stored.
// ══════════════════════════════════════════════════════════════════════════════

// ── sync_meta ─────────────────────────────────────────────────────────────────
/// Single-row table storing the last successful sync timestamp.
class SyncMeta extends Table {
  TextColumn get id => text().withDefault(const Constant('default'))();
  DateTimeColumn get lastSync => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── customers ─────────────────────────────────────────────────────────────────
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get companyName => text()();
  TextColumn get taxId => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// The customer's one agent (Riferimento) — `Customer.AgentId` on the server. A new ticket for this
  /// customer pre-fills its own Riferimento from it; the ticket's value stays authoritative after
  /// that. Nullable: most customers have none. No foreign key — the agent may not be mirrored (it
  /// travels in the sync's `agents`, and the picker reads `agents` by id, tolerating a miss).
  TextColumn get agentId => text().nullable()();

  /// Mobile phone number — `cellulare` on the wire, distinct from the landline [phone]. A
  /// technician on site calls the number on the customer card, so it has to be readable with no
  /// signal; before this column only the landline ever arrived.
  TextColumn get cellulare => text().nullable()();

  // ── fiscal identity (schema 48) ──────────────────────────────────────────────
  // The fields an Italian customer is identified by, all already on the wire inside the customer
  // entity — the mirror simply never stored them, so the "Dati fiscali" card could show only
  // P.IVA and the rest was network-only. Same field-parity gap as `numero`/`priority`/`dueDate` on
  // tickets (schema 12/20) and `agentId` above (schema 42). See `syncCursorGeneration`'s own doc
  // comment for why the delta cursor is bumped too.
  //
  // Wire names are NOT the C# property names: `fiscalCode` (CodiceFiscale), `sdiCode` (SDICode),
  // `pec` (PECEmail), `province` (Provincia). A wrong name here fails silently — the value just
  // never arrives and the card shows nothing.

  /// Codice Fiscale. Independent of [taxId]: a private individual may have this and no P.IVA.
  TextColumn get fiscalCode => text().nullable()();

  /// Codice Destinatario SDI. `0000000` means PEC-routed and `XXXXXXX` a foreign recipient — both
  /// are real values, so this is stored verbatim and never interpreted.
  TextColumn get sdiCode => text().nullable()();

  /// PEC (certified email) address.
  TextColumn get pec => text().nullable()();

  /// Province code (sigla), e.g. "RM".
  TextColumn get province => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── reference mirror (schema 37) ────────────────────────────────────────────────
// Contracts of the customers this technician's payload carries. Mirrored so the ticket wizard's
// Cliente→Contratto picker is filled offline (spec 7.4).
//
// `isActive` is carried, not filtered: a contract deactivated on the server must arrive here as a
// row with a false flag, or a device that cached it would offer it forever (spec 6.4).
class Contracts extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get name => text()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// `numero` and `codice` are both human references a technician may read off the paper contract;
  /// the picker shows whichever is present.
  TextColumn get numero => text().nullable()();
  TextColumn get codice => text().nullable()();
  IntColumn get tipo => integer().nullable()();
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Commesse (`codice`, `descrizione`) of the customers this technician's payload carries.
class Commesse extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get codice => text()();
  TextColumn get descrizione => text().nullable()();
  TextColumn get customerId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get stato => text().nullable()();
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Products / services (`ProdottoAssistenza`) of the customers this technician's payload carries.
///
/// Deliberately separate from [Assets], which mirrors the *covered* assets of this technician's
/// tickets for the checklist feature and is pruned by `checklist_reconciler`. Two scopes, two
/// lifecycles: this table answers "what can I pick for this customer", that one answers "what did
/// this ticket cover". Merging them would put the ticket form in the hands of the checklist pruner.
class ProdottiAssistenza extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get name => text()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Wire names follow the entity's own JsonPropertyName attributes: codice / categoria / marchio.
  TextColumn get codice => text().nullable()();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get categoria => text().nullable()();
  TextColumn get marchio => text().nullable()();
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Agents, mirrored only for the ones this technician's tickets already reference — the
/// "Riferimento" field. A tenant-wide agent book is explicitly not mirrored (spec 10, D-1(a)).
class Agents extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get nome => text()();
  TextColumn get email => text().nullable()();
  TextColumn get cellulare => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── maintenance template catalogue (schema 40) ─────────────────────────────────
/// The maintenance checklist templates a technician may attach to a NEW ticket as its checklist —
/// the "Modello checklist" the web form already offers — mirrored so the wizard's picker is filled
/// offline.
///
/// Mirrors [SyncMaintenanceTemplateDto] on the wire rather than the full template entity: the picker
/// needs the [name] to show and two answers about the template — whether new work may resolve it
/// ([isActive]) and which version it would resolve to ([latestPublishedVersion], null while every
/// version is still a draft). [origin] rides along because it is on the wire and describes the row,
/// the same reasoning [Contracts.isActive] records: dropping a wire field would make the mirror a
/// different set of facts than the payload.
///
/// No tenant/created/updated bookkeeping: the whole visible set is replaced wholesale on every sync
/// (see SyncService), so the row only has to answer the picker.
class MaintenanceTemplates extends Table {
  TextColumn get id => text()();

  /// MaintenanceTemplateOrigin: "System" (curated) | "Tenant" (this tenant's own), stored as the
  /// wire enum name like [Tickets.priority] rather than an int — nothing filters on it.
  TextColumn get origin => text()();

  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// The version a new ticket would resolve to today, or null while every version is still a draft
  /// or already retired. Null is a real, visible state ("cannot be attached now"), not missing data
  /// — the picker hides it.
  IntColumn get latestPublishedVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── locations ─────────────────────────────────────────────────────────────────
class Locations extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get customerId => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get country => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── tickets ───────────────────────────────────────────────────────────────────
class Tickets extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get title => text()();

  /// The per-tenant display number the office and the customer use for this job.
  ///
  /// Nullable because tickets created before numbering existed do not have one. Absent means the
  /// ticket has no number — never a reason to fall back to the id.
  TextColumn get numero => text().nullable()();

  TextColumn get description => text().nullable()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text()();
  TextColumn get assignedUserId => text().nullable()();
  IntColumn get statusId => integer()();
  IntColumn get typeId => integer()();
  TextColumn get agentId => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get technicianNotes => text().nullable()();
  TextColumn get internalNotes => text().nullable()();
  TextColumn get contractId => text().nullable()();
  TextColumn get prodottoAssistenzaId => text().nullable()();
  TextColumn get commessaId => text().nullable()();

  /// The cantiere (worksite) this ticket is linked to, when it has one — a ticket may or may not
  /// be linked to a cantiere. Already on the wire the whole time (mobile sync returns the full
  /// `Ticket` entity, which has carried `CantiereId` since it was added server-side), just never
  /// parsed or stored — same situation as `numero` (schema 12) and `priority`/`dueDate`
  /// (schema 20). See `syncCursorGeneration`'s own doc comment for why this needs a bump too.
  TextColumn get cantiereId => text().nullable()();

  /// Wire form is the enum name ("Bassa"/"Media"/"Alta"/"Urgente" — backend `TicketPriorityEnum`
  /// carries `[JsonConverter(typeof(JsonStringEnumConverter))]`), not an int. Stored as the same
  /// string rather than parsed to an enum locally, matching how `statusId`/`typeId` are looked up
  /// through `ticketStatusMapProvider` instead of a client-side enum.
  TextColumn get priority => text().nullable()();

  /// The day the office wants this job done — a CIVIL date (`yyyy-MM-dd` TEXT), not an instant.
  ///
  /// A Drift `DateTimeColumn` would store the epoch seconds and read them back through
  /// `DateTime.fromMillisecondsSinceEpoch`, which is *local*: a date pinned as UTC midnight came back
  /// as the previous calendar day on any device west of UTC, and no formatter can recover a day that
  /// was already lost on read. Same reasoning, and the same storage, as
  /// [Strumenti.calibrationExpiry] below.
  ///
  /// Read it with `parseDateOnly` and write it with `formatDateOnly` (`core/time/business_time.dart`);
  /// the wire form is unchanged (`date-time` — the backend's `UtcDateTimeConverter` reads an
  /// unspecified kind as UTC, so a date-only or a `Z`-suffixed midnight both land on the same day).
  TextColumn get dueDate => text().nullable()();

  /// Free-form labels, no catalogue behind them (see `TicketDto.tags`'s own doc comment). No
  /// list-column type exists in Drift, so stored as JSON text — same convention as
  /// `Entitlements.featuresJson`/`capabilitiesJson`, not a naive comma-join (a tag containing a
  /// literal comma would silently split wrong).
  TextColumn get tagsJson => text().nullable()();

  /// The tenant's custom-field values for this ticket ("campi aggiuntivi"), as the server's raw
  /// JSON-object text — the same double-encoded shape the backend sends (`extensionValues` is a
  /// `string?` over a Postgres `jsonb` column, so the API serializes it as a JSON *string* holding
  /// JSON). Stored verbatim rather than unpacked: the keys are tenant-defined and change over time,
  /// and the section renders whatever [ExtensionFieldDefinitions] says this tenant configured.
  ///
  /// Without this column the value of every custom field was invisible offline even though the
  /// payload has always carried it inside the ticket entity — the same field-parity gap as `numero`
  /// (schema 12) and `priority`/`dueDate` (schema 20). See `syncCursorGeneration`'s own doc
  /// comment for why this needs a bump too.
  TextColumn get extensionValues => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The tenant's custom-field definitions ("campi aggiuntivi"), mirrored from the sync payload so
/// the section renders offline — and so a rapportino written on site can still be completed field
/// by field when there is no signal.
///
/// Before this table the phone's only source was the live
/// `GET /api/extension-fields/{entityType}/definitions`; offline that call has nothing to answer
/// with, so the whole section silently disappeared on exactly the screens where the tenant's own
/// fields are filled in (rapportino Dettagli, cantiere form).
///
/// Replaced WHOLESALE on every sync, and only when the payload carries a non-empty list: the server
/// sends the complete active set each time (a soft-deactivated field has no change marker a delta
/// could see), and an empty carried list means "this caller may not read any type's definitions" —
/// not "the tenant has none". See `SyncService._replaceExtensionFieldDefinitions`.
class ExtensionFieldDefinitions extends Table {
  TextColumn get id => text()();

  /// What the entity's `extensionValues` JSON object is keyed by.
  TextColumn get key => text()();

  TextColumn get label => text()();

  /// Lowercase canonical type (`ticket`, `cantiere`, `report`, …) — the backend's own key, the same
  /// one `ExtensionFieldsApiClient` sends.
  TextColumn get entityType => text()();

  /// Free string mapped by `ExtensionFieldRenderType.of`, never an enum on the wire.
  TextColumn get fieldType => text()();

  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  BoolColumn get showInCard => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get options => text().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get defaultValue => text().nullable()();
  TextColumn get placeholder => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── schedules ─────────────────────────────────────────────────────────────────
class Schedules extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get ticketId => text().nullable()();
  DateTimeColumn get activityDate => dateTime()();

  /// TimeStart stored as total minutes since midnight (TimeSpan has no Drift equivalent)
  IntColumn get timeStartMinutes => integer()();

  /// TimeEnd stored as total minutes since midnight
  IntColumn get timeEndMinutes => integer()();
  TextColumn get userId => text()();
  IntColumn get statusId => integer()();
  TextColumn get locationId => text()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get title => text()();
  TextColumn get description => text()();

  // Who is on this schedule lives in [ScheduleAssignees]. teamLeadId, staffIds and squadraId
  // were dropped server-side (backend ADR-0009) and stopped arriving; keeping them here would
  // have left three columns that are null forever and a staffIds blob that never parses to
  // anyone — which is the shape that made team-assigned work invisible on the device.

  @override
  Set<Column> get primaryKey => {id};
}

/// Everyone on a schedule, one row per person per reason.
///
/// A row per (schedule, user) rather than a JSON list on Schedules: the list form is what the
/// server just spent a migration removing, and it cannot answer "which of my jobs am I on"
/// without reading every row and parsing each blob.
class ScheduleAssignees extends Table {
  TextColumn get scheduleId => text().references(Schedules, #id)();
  TextColumn get userId => text()();

  BoolColumn get isUserActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isDirect => boolean().withDefault(const Constant(false))();
  BoolColumn get isLead => boolean().withDefault(const Constant(false))();
  BoolColumn get isTeam => boolean().withDefault(const Constant(false))();
  BoolColumn get isLegacyStaff => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {scheduleId, userId};
}

// ── cantieri ──────────────────────────────────────────────────────────────────
class Cantieri extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// CantiereStatusEnum: Active=0, Completed=1, Cancelled=2
  IntColumn get status => integer().withDefault(const Constant(0))();
  TextColumn get customerId => text().nullable()();
  TextColumn get commessaId => text().nullable()();

  /// Client-side geocode cache for [address]/[city]/[postalCode] — there is no lat/lng anywhere
  /// on the backend `Cantiere` entity to sync instead. Populated lazily by
  /// `cantiereGeocodedLocationProvider` (cantiere_providers.dart) the first time this cantiere's
  /// detail screen is opened and geocoding succeeds; null forever for a cantiere with no address
  /// or one Nominatim couldn't resolve. Both null or both set — never written independently.
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  /// The tenant's custom-field values for this cantiere, verbatim JSON-object text — see
  /// [Tickets.extensionValues] for the wire shape and why it is stored unpacked.
  TextColumn get extensionValues => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── cantiere crew assignments (schema 43) ────────────────────────────────────
/// The crew of each cantiere this device has synced — one row per assignment, the lead flag
/// included.
///
/// Client-only mirror of `GET /api/cantieri/{id}/assegnazioni`. Before it existed that endpoint was
/// the cantiere flow's last live-only read: offline, the lead-only clock-in affordances silently
/// disappeared (`isLeadForCantiereProvider` read "not lead") and the teammate picker opened empty,
/// even though the cantiere punches themselves already queue offline. The row carries exactly what
/// its two readers need — who is on the crew and which of them is lead — and is replaced per
/// cantiere on every sync (see `SyncService._replaceCantiereCrewAssignments`), never merged field
/// by field.
///
/// No tenant/created/updated bookkeeping: nothing reads them, and the whole set for a cantiere is
/// rewritten each time the payload carries it.
class CantiereCrewAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get cantiereId => text()();

  /// The internal database Guid of the assigned technician — the same id
  /// `internalUserIdProvider` holds, not the Zitadel OIDC sub.
  TextColumn get userId => text()();

  /// Whether this person is the lead for the cantiere. A lead change must reach the device even
  /// when the cantiere row itself did not change, which is why the sync sends the crew in full
  /// rather than delta-filtered.
  BoolColumn get isLead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── ticket_statuses ───────────────────────────────────────────────────────────
class TicketStatuses extends Table {
  IntColumn get id => integer()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── ticket_types ──────────────────────────────────────────────────────────────
class TicketTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── materiali ─────────────────────────────────────────────────────────────────
/// The tenant's active users, mirrored so the rapportino staff step can offer a picker.
///
/// Without this table the app had nothing to pick from offline, so the step asked the technician
/// to type a colleague's user id — and invented one when they left it blank. Hours attributed to a
/// fabricated id reach payroll and the customer's invoice.
///
/// Read-only mirror: replaced wholesale on every sync, never written by the device.
class Colleagues extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The people to phone at a customer site, mirrored so the customer screen's *Contatti* section
/// renders from the local cache.
///
/// It used to call `GET /api/customers/{id}/contacts` on every open and show an error card when the
/// network was gone — standing in front of the machine is exactly where a technician needs the
/// number. Read-only mirror: the office owns these rows, and the sync REPLACES each customer's list
/// (a removed contact has no tombstone to carry its removal, so merging would keep it forever).
///
/// `CustomerContactRow`, not the default `CustomerContact`: `CustomerContactApiClient` already owns
/// that name for the wire model, and a screen holding both would hit an ambiguous import.
@DataClassName('CustomerContactRow')
class CustomerContacts extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get name => text()();
  TextColumn get role => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The tenant's entitlements, mirrored so the app can gate features without a network round trip.
///
/// One row, id `current`. Replaced whole on every successful `/api/Auth/me`; **never cleared on
/// failure** — see `EntitlementRepository` for why that asymmetry is the whole point.
class Entitlements extends Table {
  TextColumn get id => text()();

  /// Granted module keys, JSON array. Mirrors ModuleKeys on the server.
  TextColumn get featuresJson => text()();

  /// Canonical `module.resource.action` keys, JSON array.
  TextColumn get capabilitiesJson => text()();

  /// `field` or `office`. A field seat is the mobile-only seat.
  TextColumn get seatType => text()();

  /// When this was last confirmed by the server. Shown to the user, never used to expire the row.
  DateTimeColumn get fetchedAt => dateTime()();

  /// `Trialing` / `Active` / `PastDue` / `GracePeriod` / `Suspended` / `Canceled` — mirrors the
  /// server's `SubscriptionStatusEnum`. Nullable only for rows written before this column existed;
  /// treated as unknown, not as active, everywhere it is read.
  TextColumn get subscriptionStatus => text().nullable()();

  /// "Both" (default) / "QrOnly" / "ButtonOnly" — the EFFECTIVE value the server already resolved
  /// (tenant default + user override + Kiosk-entitlement downgrade), never recomputed on-device.
  /// Nullable only for rows written before this column existed — read as "Both" everywhere.
  TextColumn get clockInMethod => text().nullable()();

  /// The one deliberate exception to this table's "no answer means allow" asymmetry (see
  /// EntitlementRepository's own doc comment): set only when the server has positively confirmed,
  /// via a structured error code on /auth/me (not just any failure), that this specific user has
  /// been deactivated. Every other failure — offline, timeout, 5xx — leaves this column untouched.
  BoolColumn get isAccountDeactivated => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Materiali extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get unitOfMeasure => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get marca => text().nullable()();
  RealColumn get purchasePrice => real().nullable()();
  RealColumn get salePrice => real().nullable()();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── magazzini ───────────────────────────────────────────────────────────────
/// The tenant's active warehouses, mirrored so a rapportino material line can name its source
/// with no signal.
///
/// Both reads behind that were live REST calls: `furgoneDiUserProvider` (the technician's own van,
/// the default source for a line) and `magazziniProvider` (the "cambia magazzino" override). Offline
/// they both failed, the dialog opened with no default, and the line was saved with a null
/// `magazzinoId` — the report recorded the material but the warehouse provenance, which the stock
/// movement is keyed on, was gone server-side and unrecoverable.
///
/// Read-only mirror: replaced wholesale on every sync (`MobileUserSyncResult.Magazzini` carries
/// every active warehouse, no delta filter), never written by the device. Active only, so an admin
/// deactivating a warehouse removes it from the phone with no separate delete.
class Magazzini extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get nome => text()();

  /// `"Sede"` or `"Furgone"` — `MagazzinoTipoEnum` serialises as its label, the same string the
  /// REST endpoints and [MagazzinoDto] already carry.
  TextColumn get tipo => text()();

  /// For a Furgone: the technician it is assigned to. Null for a Sede, and the field that lets
  /// "my van" resolve offline without a per-user lookup.
  TextColumn get assegnatoUserId => text().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── ticket_materiali ─────────────────────────────────────────────────────────
// Fabbisogno: a ticket's planned/required materials. Mirrors the backend `TicketMateriale`
// entity 1:1 (raw field names, not the Italian-translated shape the per-ticket detail REST
// endpoint's own response DTO uses — that endpoint stays as the online source of truth; this
// table is the offline mirror synced via MobileUserSyncResult.TicketMateriali). Read-only on the
// device: mobile only ever reads fabbisogno, never writes to it.
class TicketMateriali extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get ticketId => text()();
  TextColumn get materialeId => text().nullable()();
  TextColumn get freeTextName => text().nullable()();
  RealColumn get quantity => real()();
  TextColumn get unitOfMeasure => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── materiale_barcodes ──────────────────────────────────────────────────────
//
// Local mirror of MaterialeBarcode (backend), synced alongside its parent Materiali row so a
// barcode scan can resolve to a material offline. See SyncMaterialeBarcodeDto's own doc comment
// (backend) for why this is delta-filtered independently of Materiali's own UpdatedAt.
class MaterialeBarcodes extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get materialeId => text()();
  TextColumn get barcode => text()();
  TextColumn get barcodeType => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── draft_reports ─────────────────────────────────────────────────────────────
/// Mirrors Report entity. Holds both server-synced drafts and locally-created ones.
class DraftReports extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get title => text()();
  TextColumn get scheduleId => text().nullable()();
  TextColumn get ticketId => text().nullable()();
  TextColumn get customerId => text().nullable()();

  /// The cantiere this rapportino is about, when it was created from a Cantiere rather than a
  /// Ticket. Was tracked only in `ReportEditorState.cantiereId` — never a DB column — so it
  /// never survived an autosave: `_buildHeaderCompanion()` had no column to put it in, and
  /// only `cantiereFreeText` (the display fallback) made it into `metadataJson`. See schema v21.
  TextColumn get cantiereId => text().nullable()();
  TextColumn get details => text().nullable()();

  /// GPS/free-text fallback metadata (customerFreeText, locationFreeText, ticketFreeText,
  /// cantiereFreeText, workAddress, gpsLatitude, gpsLongitude) packed as a JSON string.
  ///
  /// Deliberately a separate column from [details]: the editor's autosave used to pack this same
  /// metadata directly into [details], silently overwriting the technician's actual typed
  /// description on every keystroke before it ever reached the backend or the customer-facing
  /// PDF. See ReportEditorNotifier._buildMetadataJson in report_editor_providers.dart.
  TextColumn get metadataJson => text().nullable()();

  TextColumn get insertedUserId => text()();
  TextColumn get locationId => text()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get documentTemplateId => text().nullable()();
  TextColumn get customerSignatureAllegatoId => text().nullable()();
  TextColumn get technicianSignatureAllegatoId => text().nullable()();
  TextColumn get technicianNotes => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();

  /// Whether a model produced any of this rapportino's text.
  ///
  /// Persisted on the draft rather than held in memory: a technician generates a draft, closes
  /// the app, comes back an hour later and submits. If the flag lived only in the editor state
  /// the provenance would quietly disappear across that restart, and a report that was in fact
  /// AI-assisted would be filed as hand-written.
  BoolColumn get isAiAssisted => boolean().withDefault(const Constant(false))();

  /// ReportStatoEnum string: Bozza, Inviato, Controllato, Fatturato
  TextColumn get stato => text().withDefault(const Constant('Bozza'))();
  DateTimeColumn get inviatoAt => dateTime().nullable()();
  DateTimeColumn get controllatoAt => dateTime().nullable()();
  TextColumn get controllatoDa => text().nullable()();
  DateTimeColumn get fatturatoAt => dateTime().nullable()();
  BoolColumn get materialiNotRequired => boolean().withDefault(const Constant(false))();
  TextColumn get customerSignoffText => text().nullable()();
  DateTimeColumn get customerSignoffAt => dateTime().nullable()();

  /// What was found wrong / what was done (backend `Report.Diagnosi` / `Report.Soluzione`).
  ///
  /// Three-valued on purpose, mirroring the submit rule in `ReportSubmitService`: null = the
  /// technician never touched it, so the submit omits it and the server keeps whatever it holds
  /// (e.g. text the AI copilot's Confirm wrote); empty string = the technician cleared it; any
  /// other text replaces it. Do not collapse empty into null anywhere on the write path.
  TextColumn get diagnosi => text().nullable()();
  TextColumn get soluzione => text().nullable()();

  /// The tenant's custom-field values for this rapportino, verbatim JSON-object text — see
  /// [Tickets.extensionValues] for the wire shape and why it is stored unpacked.
  ///
  /// Server-authored only: the values are written through
  /// `PUT /api/extension-fields/report/{id}/values` by the Dettagli step, and read back here so a
  /// rapportino opened offline still shows what was recorded for it.
  TextColumn get extensionValues => text().nullable()();

  /// True for drafts that only exist locally (not yet submitted).
  BoolColumn get isLocalOnly => boolean().withDefault(const Constant(false))();

  /// Submission state machine:
  /// draft | readyToSubmit | uploadingMedia | submitting | submitted | failed
  TextColumn get submissionState => text().withDefault(const Constant('draft'))();

  /// Stable idempotency key (UUID string) persisted on first submit attempt.
  /// Reused on retries so the server deduplicates duplicate submits.
  TextColumn get idempotencyKey => text().nullable()();

  /// Human-readable error message from the last failed attempt (null when ok).
  TextColumn get submissionError => text().nullable()();

  /// Consecutive failed automatic send attempts whose cause was transient (see
  /// [submissionErrorTransient]). The submission queue auto-retries a transient failure on
  /// reconnect/resume/startup until this reaches its cap; a manual "Riprova" resets it to 0.
  /// Client-authored only, never synced.
  IntColumn get submissionAttempts => integer().withDefault(const Constant(0))();

  /// True when the last failure was worth retrying unattended (transport error, HTTP 5xx, 408,
  /// 429). False for permanent causes (other 4xx, missing local file), which stay `failed`
  /// until the technician acts. Client-authored only, never synced.
  BoolColumn get submissionErrorTransient => boolean().withDefault(const Constant(false))();

  /// True once the technician has explicitly cleared their technician signature via the
  /// "Cancella" button (`ReportEditorNotifier.clearTechnicianSignature`).
  ///
  /// `StepRiepilogo` is recreated (fresh `initState`) every time its containing bottom sheet is
  /// reopened, and its pre-fill logic's only other guard (`technicianSignatureAllegatoId == null`)
  /// is exactly the state Cancella itself produces — so without this column, closing and
  /// reopening the sheet after an explicit Cancella would silently re-fetch and reinstate the
  /// very signature the technician just removed. This flag survives that recreation (it's on the
  /// persisted draft row, not in memory) and is checked — never auto-reset — by the pre-fill
  /// logic before it fetches. It resets to false the moment a genuine new technician signature is
  /// saved (drawn or typed), since that is itself a fresh, deliberate signing act.
  BoolColumn get technicianSignaturePrefillSuppressed =>
      boolean().withDefault(const Constant(false))();

  /// "Da tornare" / "Serve un secondo intervento" — set from the Riepilogo step alongside the
  /// submit action. Mirrors `SubmitReportRequest.RichiedeSecondoIntervento` on the backend: when
  /// true and this draft is linked to a ticket, submitting atomically moves that ticket to the
  /// tenant's `RequiresFollowUp`-flagged status (see `ReportSubmitService.SubmitAsync`).
  ///
  /// Persisted like every other Riepilogo boolean (see `materialiNotRequired`), not held only in
  /// memory: a technician who ticks this and then closes the app mid-compilation must not lose
  /// the flag before ever reaching the submit button.
  BoolColumn get richiedeSecondoIntervento => boolean().withDefault(const Constant(false))();

  /// True once the Strumenti step has pre-filled this draft from the technician's kit
  /// (`strumenti.isMine`). Persisted so a technician who deselects an instrument is never
  /// re-filled on the next open; set true on import of a server draft (the server's selection wins).
  /// Client-authored only, never synced.
  BoolColumn get strumentiPrefilled => boolean().withDefault(const Constant(false))();

  /// The structured reason of the last PERMANENT submit failure (JSON of `SubmitProblem`): which
  /// required controls / instruments / assets the server rejected, so Riepilogo can reopen the
  /// right place instead of showing one opaque sentence. Null when the last failure had no
  /// structured shape or there was none. Client-authored only, never synced.
  TextColumn get submissionProblemJson => text().nullable()();

  /// The report row's opaque version (`xmin` as a decimal string) as the phone last *saw* the
  /// server's copy — the `version` field of `GET /api/reports/{id}`. Persisted at every point a
  /// server report is mirrored into a local draft (import, cantiere-create) and read back at submit
  /// time as `SubmitReportRequest.expectedVersion`; the server refuses the submit with a 409 if the
  /// office edited the report after this version was captured, instead of silently overwriting it.
  ///
  /// It MUST be captured at ingestion, never fetched at submit time: a version read immediately
  /// before submitting always matches the row it is compared against, so the guard would detect
  /// nothing while looking correct. Null means "this draft was never on the server", and the submit
  /// then omits the field (the server skips the check — today's behaviour for a brand-new offline
  /// draft). Client-authored only, never synced.
  TextColumn get expectedVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_staff ──────────────────────────────────────────────────────────────
class ReportStaffTable extends Table {
  @override
  String get tableName => 'report_staff';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get reportId => text()();
  TextColumn get userId => text()();
  RealColumn get hoursWorked => real().nullable()();
  RealColumn get kmTraveled => real().withDefault(const Constant(0.0))();
  TextColumn get vehicle => text().nullable()();
  RealColumn get costPerKm => real().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startTime => dateTime().nullable()();
  DateTimeColumn get endTime => dateTime().nullable()();
  IntColumn get pauseMinutes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_materiali ──────────────────────────────────────────────────────────
class ReportMateriali extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get reportId => text()();
  TextColumn get materialeId => text().nullable()();
  TextColumn get freeTextName => text().nullable()();
  RealColumn get quantity => real()();
  TextColumn get unitOfMeasure => text().nullable()();
  RealColumn get unitPrice => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get magazzinoId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_controlli ──────────────────────────────────────────────────────────
class ReportControlli extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get reportId => text()();
  TextColumn get controlId => text()();
  TextColumn get stringValue => text().nullable()();
  BoolColumn get boolValue => boolean().nullable()();
  DateTimeColumn get dateValue => dateTime().nullable()();

  /// The answer for a Number-type control (backend's ControlTypeEnum.Number, migration 27).
  RealColumn get numberValue => real().nullable()();

  /// Per-answer remark (backend `ReportControlObservation.Note`, max 2000). A note never counts as
  /// an answer; a blank/omitted note never erases a stored one server-side.
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── cached_ticket_controls ──────────────────────────────────────────────────
/// Last successfully fetched checklist (`GET /api/tickets/{id}/controls`) for a ticket, so the
/// rapportino's Controlli step can still be viewed and answered while offline mid-draft.
///
/// Every other section of the offline-first rapportino form (materials, staff, photos,
/// signatures, GPS) works with zero network at capture time; the checklist used to be the one
/// exception, throwing [TicketDetailOfflineException] with nothing to show. One row per ticket,
/// overwritten on every successful online fetch — see `TicketControlsCacheRepository`. Answers
/// recorded against a cached checklist are ordinary [ReportControlli] rows, already queued for
/// submit the same way as the rest of the draft; caching the checklist's *questions* is the only
/// piece that was missing.
class CachedTicketControls extends Table {
  TextColumn get ticketId => text()();

  /// The raw `List<TicketControlGroupDto>` tree, serialized to JSON by
  /// `TicketControlsCacheRepository` (that DTO has no `toJson` of its own — it only ever came
  /// from the server before now).
  TextColumn get controlsJson => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ticketId};
}

// ── work_sessions (Timbra) ────────────────────────────────────────────────────
/// Local-only clock-in / clock-out sessions for the Timbra feature.
/// When the backend endpoint (D6) is implemented, these rows will be synced up.
///
/// event_type values:
///   'ingresso'  — clock-in (shift start)
///   'fine'      — clock-out (shift end)
///   'pausa'     — pause start
///   'ripresa'   — pause end (resume)
class WorkSessions extends Table {
  @override
  String get tableName => 'work_sessions';

  TextColumn get id => text()();
  DateTimeColumn get eventTime => dateTime()();

  /// One of: ingresso | fine | pausa | ripresa
  TextColumn get eventType => text()();

  /// Optional notes (future use).
  TextColumn get notes => text().nullable()();

  /// True while not yet synced to the backend.
  BoolColumn get isPendingSync => boolean().withDefault(const Constant(true))();

  /// GPS position captured at punch time, for `ingresso`/`ripresa` (interval-opening) events —
  /// null for `fine`/`pausa` and whenever the technician has GPS off or permission was never
  /// granted. Simple timbra still works with no position at all (see cantiere_timbra_screen's own
  /// copy: "La timbratura normale... funziona senza GPS"); this only stops the app from silently
  /// discarding a position it could have captured for free instead of ever sending it. Mirrors the
  /// single "GPS latitude/longitude at punch time" pair `MobileSessionDto` accepts server-side.
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  /// Device-reported GPS accuracy radius, in meters, at the moment latitude/longitude were
  /// captured. Capture-only, mirrors `WorkLog.GpsAccuracyMeters` server-side — null whenever no
  /// position was captured or the device didn't report an accuracy value.
  RealColumn get gpsAccuracyMeters => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── cantiere_punches (Cantiere Timbra) ────────────────────────────────────────
/// Local-only clock-in / clock-out events for cantiere (worksite) timbratura.
///
/// One row per raw event (mirrors [WorkSessions]), not per session: an
/// 'ingresso' event carries the site context (cantiereId/customerId/ticketId)
/// and the arrival position; the matching 'uscita' event only needs a
/// timestamp. `cantiere_session_assembler.dart` folds pairs of these into the
/// intervals the backend's `/api/CantiereWorkLog/mobile/sessions` upsert
/// expects.
///
/// event_type values:
///   'ingresso' — arrive at site (opens an interval)
///   'uscita'   — leave site (closes the open interval)
class CantierePunches extends Table {
  TextColumn get id => text()();
  DateTimeColumn get eventTime => dateTime()();

  /// One of: ingresso | uscita
  TextColumn get eventType => text()();

  /// Site context — set on 'ingresso', null on 'uscita' (inherited from the
  /// paired opener by the assembler).
  TextColumn get cantiereId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get ticketId => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  /// Free-text work description, carried through to `CantiereMobileSessionDto.description` on
  /// sync — see `CantiereWorkLogController.MobileSessions`. Set on 'ingresso'; on 'uscita' it is
  /// the note typed on the clock-out screen, which the assembler lets win (the online `end` route
  /// overwrites the row's Description the same way).
  TextColumn get description => text().nullable()();

  /// Safety note typed on the clock-out screen. 'uscita' only — that screen is the only place the
  /// app ever asks for it.
  TextColumn get safetyNotes => text().nullable()();

  /// The clock-in screen's rich fields. 'ingresso' only: they describe what was true on arrival,
  /// and the server writes them when the punch is created, never on a later close. Before schema
  /// 51 they travelled only through the online `start` call, so a technician who clocked in with no
  /// signal lost the work order, the equipment, the crew size and the weather the office prices
  /// the job from.
  TextColumn get workOrderNumber => text().nullable()();
  TextColumn get equipmentUsed => text().nullable()();
  IntColumn get teamSize => integer().nullable()();
  TextColumn get weatherConditions => text().nullable()();

  /// GPS the phone recorded at clock-out. 'uscita' only; [latitude]/[longitude] stay the arrival
  /// fix on 'ingresso'.
  RealColumn get departureLatitude => real().nullable()();
  RealColumn get departureLongitude => real().nullable()();

  /// True while not yet synced to the backend.
  BoolColumn get isPendingSync => boolean().withDefault(const Constant(true))();

  /// Human-readable error message from the last failed sync attempt (null when ok).
  TextColumn get syncError => text().nullable()();

  /// Reconciliation marker — mirrors `WorkSessions.notes` (`reconciledOrphanMarker`). Set by
  /// `CantiereWorkLogReconciler` on an 'ingresso' the server has already closed elsewhere, so
  /// `CantiereTimbraSyncService` never resends it. See cantiere_work_log_reconciler.dart.
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── ticket_timers (Ore tab and ticket timer bar) ──────────────────────────────
/// The caller's own ticket timer sessions: the server's rows, plus any row this device started
/// offline and has not managed to send yet.
///
/// Unlike [WorkSessions] (raw punch events for simple attendance) and [CantierePunches] (raw site
/// events), a ticket timer is already a session — the backend stores it as one row and its mobile
/// upsert takes start/end instants directly. So this table mirrors that row rather than folding
/// events, and `clientId` is the idempotency key the batch endpoint upserts on.
///
/// `workDate`/`startSeconds`/`endSeconds` are the Rome-local frame every ticket worklog reader
/// uses; `startUtc`/`endUtc` are the true instants. A row born offline has the instants first and
/// the local frame is derived for display; a server row carries both (the instants are null on
/// legacy rows written before the instant columns existed).
class TicketTimers extends Table {
  @override
  String get tableName => 'ticket_timers';

  /// Server id once known; the local uuid before the first successful upload.
  TextColumn get id => text()();

  /// The idempotency key. Device rows are born with the local uuid as their client id; a row
  /// created in the office or online carries no client id on the wire, and stays null here.
  TextColumn get clientId => text().nullable()();

  TextColumn get ticketId => text()();

  /// The owning user's internal id, so the offline list renders the same shape as the server's.
  TextColumn get userId => text().withDefault(const Constant(''))();

  /// Rome-local date and time of day; null only for a device row not yet sent.
  DateTimeColumn get workDate => dateTime().nullable()();
  IntColumn get startSeconds => integer().nullable()();
  IntColumn get endSeconds => integer().nullable()();

  DateTimeColumn get startUtc => dateTime().nullable()();
  DateTimeColumn get endUtc => dateTime().nullable()();

  IntColumn get approvalStatus => integer().nullable()();
  TextColumn get description => text().nullable()();
  BoolColumn get isManualEntry => boolean().withDefault(const Constant(false))();

  /// True while this row is a session the server has not confirmed.
  BoolColumn get isPendingSync => boolean().withDefault(const Constant(false))();

  /// Human-readable reason the last upload attempt was refused (null when nothing is wrong).
  TextColumn get syncError => text().nullable()();

  /// The server row's `updatedAt`, when it sent one.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── notifications ─────────────────────────────────────────────────────────────
/// Cached notifications from the backend. Used for offline display of the
/// notification center. Synced via GET /api/notifications; individual
/// read-state is updated locally and synced back via PUT.
class AppNotifications extends Table {
  @override
  String get tableName => 'notifications';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get message => text()();

  /// Notification type string (e.g. TicketAssigned, ScheduleReminder)
  TextColumn get type => text()();

  /// Delivery type string (InApp, Push, Email)
  TextColumn get deliveryType => text()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get readAt => dateTime().nullable()();
  TextColumn get relatedEntityId => text().nullable()();
  TextColumn get relatedEntityType => text().nullable()();
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
  BoolColumn get isDelivered => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_allegati ───────────────────────────────────────────────────────────
/// Local attachment metadata. Before upload, storagePath is a local file path.
class ReportAllegati extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get fileName => text()();
  TextColumn get contentType => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get storagePath => text()();
  TextColumn get url => text()();

  /// AllegatoEntityTypeEnum: Ticket=0, Report=1, Materiale=2
  IntColumn get entityType => integer()();
  TextColumn get entityId => text()();
  TextColumn get uploadedByUserId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// True when this file has not yet been uploaded to the server.
  BoolColumn get isPendingUpload => boolean().withDefault(const Constant(false))();

  /// AllegatoKindEnum: UserUpload=0, SystemArtifact=1 (captured signatures). Only the server sends
  /// this today; a row this device wrote before schema 43 keeps the default, which is what every
  /// locally-captured file is.
  IntColumn get kind => integer().withDefault(const Constant(0))();

  /// SHA-256 of the file's bytes, lowercase hex — the value the sync delivers for a server row and
  /// the value `AttachmentService` computes for one uploaded from here. Null on rows written
  /// before the column existed, and on a local capture that has never reached the server.
  ///
  /// Its reason for existing is the attachment cache (O-8c): a file identifies itself by content,
  /// so a re-uploaded or re-sent attachment is the same cache entry, and a changed one is not.
  TextColumn get contentHash => text().nullable()();

  /// GPS position captured at the moment this allegato was recorded (signatures only — see
  /// `ReportEditorNotifier.saveCustomerSignature`/`saveTechnicianSignature`). Null when the
  /// device denied/lacked location, or for allegati that never carry a position (photos):
  /// GPS must never block capture, so a missing value here means exactly that, not a bug.
  RealColumn get capturedLatitude => real().nullable()();
  RealColumn get capturedLongitude => real().nullable()();

  /// UTC timestamp of capture — set unconditionally alongside the (possibly null) coordinates
  /// above, so every signature carries a "when" even on the devices/moments GPS is unavailable.
  DateTimeColumn get capturedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── pending_tickets ───────────────────────────────────────────────────────────
/// Local outbox for tickets created while the device might be offline.
///
/// Unlike [DraftReports] (which carries a server-honoured idempotency key),
/// ticket creation (`POST /api/Tickets`) has no client-supplied dedup field.
/// So this table's state machine is stricter than the rapportino queue's:
///
///   pendingSync ──(never sent — device was offline at create time)──► submitting
///   submitting  ──(200 OK)──────────────────────────────────────────► submitted
///   submitting  ──(error — outcome on the server is now unknown)────► failed
///
/// `failed` rows are NEVER auto-retried by [TicketCreationQueue.processAll]:
/// the create request may already have reached the server, so resending it
/// automatically could create a duplicate, customer-visible ticket. Only
/// `pendingSync` rows — created while genuinely offline, so the request was
/// never sent at all — are safe to retry automatically on reconnect. A
/// `failed` row requires an explicit, user-initiated retry.
class PendingTickets extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();

  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text()();
  TextColumn get assignedUserId => text().nullable()();
  IntColumn get statusId => integer()();
  IntColumn get typeId => integer()();

  /// TicketPriorityEnum: Bassa | Media | Alta | Urgente. Sent on the wire as `priorita`
  /// (backend's `[JsonPropertyName("priorita")]`, string-serialized — see TicketPriorityEnum.cs).
  /// Defaults to "Media" to match the backend's own default when a mobile-created ticket predates
  /// this column or the picker is left untouched.
  TextColumn get priorita => text().withDefault(const Constant('Media'))();

  /// pendingSync | submitting | submitted | failed
  TextColumn get state => text().withDefault(const Constant('pendingSync'))();

  /// Human-readable error from the last failed attempt (null when ok).
  TextColumn get error => text().nullable()();

  /// Set once the server confirms creation — the real Ticket.id.
  TextColumn get serverTicketId => text().nullable()();

  /// CIVIL date (`yyyy-MM-dd` TEXT), same as [Tickets.dueDate] — see its own doc comment for why a
  /// `DateTimeColumn` is the wrong storage for a day the office named. Client-authored (this row is
  /// the create-path outbox, never delta-synced), so no `syncCursorGeneration` bump.
  TextColumn get dueDate => text().nullable()();
  TextColumn get technicianNotes => text().nullable()();
  TextColumn get agentId => text().nullable()();

  /// Reference fields the create wizard now collects, sent on the wire by [TicketApiClient].
  /// Null for every ticket queued before this column existed — and legal, since none of them is
  /// required to create a ticket.
  TextColumn get contractId => text().nullable()();
  TextColumn get commessaId => text().nullable()();
  TextColumn get cantiereId => text().nullable()();

  /// The maintenance checklist template the wizard chose to attach, sent as `maintenanceTemplateId`.
  /// Null means "let the server resolve it from type/contract" — the wizard's default option — which
  /// is why the request body omits the key rather than sending null (see TicketApiClient.createTicket).
  TextColumn get maintenanceTemplateId => text().nullable()();

  /// Covered products, JSON-encoded — same storage as [Tickets.tagsJson] (its doc comment has the
  /// reasoning). A JSON list rather than a join table because nothing reads it relationally: it is
  /// carried to the server verbatim and never queried by id.
  TextColumn get prodottoAssistenzaIdsJson => text().nullable()();

  /// The request field a rejected reference referred to ("customerId"), set when the server answered
  /// 404 with that field in the problem body's ROOT — `ErrorResponse : ProblemDetails` serializes
  /// `Extensions` flat, so it is `{"code":"not_found","field":"customerId"}`, not nested under an
  /// `extensions` key (see [ProblemDetails]). Non-null means the row is waiting on a human: it is
  /// offered for repair and left out of BOTH automatic retry sweeps (see
  /// [PendingTicketRepository.getByState]), because the id the server refused would be sent again
  /// unchanged. Cleared by a repair write. Null is the honest answer for every row written before
  /// this column existed.
  TextColumn get repairableField => text().nullable()();

  /// Free-form labels — same JSON-text storage as `Tickets.tagsJson` (its own doc comment has
  /// the full reasoning). Client-authored, never delta-synced from the server, same as every
  /// other column on this table — no syncCursorGeneration bump needed.
  TextColumn get tagsJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local outbox for a ticket attachment picked (camera/gallery) from the ticket-detail Allegati
/// tab while offline, or whose upload otherwise didn't complete immediately.
///
/// Mirrors [PendingTickets]'s shape, but the retry policy is stricter: unlike ticket creation
/// (which carries `clientId` so a resend is deduplicated server-side — see
/// TicketCreationQueue's doc comment), `POST /api/tickets/{id}/attachments` has no
/// client-supplied idempotency key. A `failed` row's outcome on the server is therefore genuinely
/// unknown, and auto-retrying it risks attaching the same photo twice. Only `pendingSync` rows —
/// created while genuinely offline, so the request was never sent — are safe to retry
/// automatically; `failed` requires an explicit, user-initiated retry (see
/// TicketAttachmentUploadQueue).
class PendingTicketAttachments extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();

  TextColumn get ticketId => text()();

  /// Absolute path to the locally captured/picked file — the source for the eventual upload.
  TextColumn get localPath => text()();
  TextColumn get fileName => text()();
  TextColumn get contentType => text()();
  IntColumn get sizeBytes => integer()();

  /// pendingSync | submitting | submitted | failed
  TextColumn get state => text().withDefault(const Constant('pendingSync'))();

  /// Human-readable error from the last failed attempt (null when ok).
  TextColumn get error => text().nullable()();

  /// Set once the server confirms the upload — the real Allegato id.
  TextColumn get serverAttachmentId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── control_groups ──────────────────────────────────────────────────────────
/// Section tree of the synced checklists (`SyncControlGroupDto`). Shared by every ticket that uses
/// the same template version, so rows are upserted and garbage-collected (see
/// `applyChecklistBatch`), not replaced per ticket.
@DataClassName('ControlGroupRow')
class ControlGroups extends Table {
  TextColumn get id => text()();
  TextColumn get parentGroupId => text().nullable()();
  TextColumn get maintenanceTemplateVersionId => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── ticket_controls ─────────────────────────────────────────────────────────
/// The materialised checklist rows of a ticket, ticket-level (`prodottoAssistenzaId` null) and
/// per-asset. The ids are the `ticketControlId` a rapportino's answers reference. Replaced
/// wholesale per ticket by `applyChecklistBatch`; a row the server stopped sending but a local
/// Bozza already answered is kept with [isRetained] (the server still accepts the observation).
@DataClassName('TicketControlRow')
class TicketControls extends Table {
  TextColumn get id => text()();
  TextColumn get ticketId => text()();
  TextColumn get prodottoAssistenzaId => text().nullable()();
  TextColumn get templateControlId => text()();

  /// Version-independent control identity: the key for bulk actions across assets pinned to
  /// different template versions.
  TextColumn get controlLineageId => text()();
  TextColumn get groupId => text()();
  TextColumn get label => text()();
  TextColumn get description => text().nullable()();

  /// Wire name of `ControlTypeEnum` ('Text', 'Number', ...), parsed with `controlTypeFromWire`.
  TextColumn get type => text()();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();

  /// JSON array string of choices for Options controls.
  TextColumn get options => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 'Pending' | 'Completed' | 'NotApplicable' (the ticket already holds an answer: multi-visit).
  TextColumn get status => text().withDefault(const Constant('Pending'))();
  TextColumn get stringValue => text().nullable()();
  BoolColumn get boolValue => boolean().nullable()();
  DateTimeColumn get dateValue => dateTime().nullable()();
  RealColumn get numberValue => real().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isRetained => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── ticket_assets ───────────────────────────────────────────────────────────
/// Assets (libretti and children) a ticket covers. `maintenanceTemplateVersionId != null` means
/// the asset is templated and its answers are `ticket_controls` rows; null means legacy
/// Controllato/Note (read-only here: `PUT .../asset-progress` is online-only and out of scope).
@DataClassName('TicketAssetRow')
class TicketAssets extends Table {
  TextColumn get ticketId => text()();
  TextColumn get prodottoAssistenzaId => text()();
  BoolColumn get controllato => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  TextColumn get maintenanceTemplateVersionId => text().nullable()();

  @override
  Set<Column> get primaryKey => {ticketId, prodottoAssistenzaId};
}

// ── assets ──────────────────────────────────────────────────────────────────
/// Identity of covered assets (`SyncAssetDto`). `librettoIdsJson` is a JSON array of the librettos
/// (among the synced covered assets) this asset belongs to; an asset can sit under two.
@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get matricola => text().nullable()();
  TextColumn get librettoIdsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── strumenti ───────────────────────────────────────────────────────────────
/// Active tenant instruments (`SyncStrumentoDto`), replaced wholesale on every sync that carries
/// the member (a user who loses `team.strumento.read` loses the cache). The expiry is a CIVIL date
/// stored as 'yyyy-MM-dd' TEXT: a Drift DateTimeColumn would come back local and show the previous
/// day west of UTC (see the dueDate bug in MORNING.md).
@DataClassName('StrumentoRow')
class Strumenti extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get matricola => text()();
  TextColumn get calibrationExpiry => text().nullable()();
  TextColumn get certificateReference => text().nullable()();
  BoolColumn get isMine => boolean().withDefault(const Constant(false))();

  /// Who has the instrument in charge: the id the office knows it by, and the display name the
  /// rapportino shows. Both null when it sits on the shelf — never an empty string, so the picker
  /// can tell "unassigned" from "someone we could not name".
  TextColumn get holderUserId => text().nullable()();
  TextColumn get holderName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_strumenti ────────────────────────────────────────────────────────
/// The instruments selected on a rapportino. Two origins in one table, like `draft_reports`:
/// server rows (isLocal false; synced down for drafts this device does not own locally) and the
/// selection authored on this device (isLocal true; never touched by sync). `expiredAtUse` is the
/// SERVER's last computed value, display only: it is never sent.
@DataClassName('ReportStrumentoRow')
class ReportStrumenti extends Table {
  TextColumn get id => text()();
  TextColumn get reportId => text()();
  TextColumn get strumentoId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get matricola => text()();
  TextColumn get calibrationExpiry => text().nullable()();
  TextColumn get certificateReference => text().nullable()();
  BoolColumn get expiredAtUse => boolean().withDefault(const Constant(false))();
  BoolColumn get expiredAcknowledged => boolean().withDefault(const Constant(false))();
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();

  /// Free text, how the instrument was used on this rapportino. Optional, max 2000 chars server-side.
  TextColumn get usageDescription => text().nullable()();

  /// Free text, the outcome (esito) of using the instrument. Optional, max 2000 chars server-side.
  TextColumn get outcome => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── checklist_omitted_tickets ───────────────────────────────────────────────
/// Tickets whose checklist the server left out of a sync (5000-row cap). The phone keeps what it
/// holds for them and re-requests them (see `refetchOmittedChecklists`); [attempts] bounds that.
@DataClassName('ChecklistOmittedTicketRow')
class ChecklistOmittedTickets extends Table {
  TextColumn get ticketId => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {ticketId};
}

// ══════════════════════════════════════════════════════════════════════════════
// Database class
// ══════════════════════════════════════════════════════════════════════════════

@DriftDatabase(
  tables: [
    SyncMeta,
    Customers,
    Locations,
    Tickets,
    Schedules,
    ScheduleAssignees,
    Cantieri,
    TicketStatuses,
    TicketTypes,
    Materiali,
    TicketMateriali,
    MaterialeBarcodes,
    DraftReports,
    ReportStaffTable,
    ReportMateriali,
    ReportControlli,
    ReportAllegati,
    WorkSessions,
    AppNotifications,
    CantierePunches,
    TicketTimers,
    PendingTickets,
    Colleagues,
    CustomerContacts,
    Entitlements,
    PendingTicketAttachments,
    CachedTicketControls,
    ControlGroups,
    TicketControls,
    TicketAssets,
    Assets,
    Strumenti,
    ReportStrumenti,
    ChecklistOmittedTickets,
    Contracts,
    Commesse,
    ProdottiAssistenza,
    Agents,
    MaintenanceTemplates,
    CantiereCrewAssignments,
    ExtensionFieldDefinitions,
    Magazzini,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 51;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _createChecklistIndexes();
        await _createReferenceIndexes();
        await _createCantiereCrewIndexes();
        await _createCustomerContactIndexes();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // M5: add submission state fields to draft_reports
          await m.addColumn(draftReports, draftReports.submissionState);
          await m.addColumn(draftReports, draftReports.idempotencyKey);
          await m.addColumn(draftReports, draftReports.submissionError);
        }
        if (from < 3) {
          // Timbra: add work_sessions table for local clock-in/out (D6 backend pending)
          await m.createTable(workSessions);
        }
        if (from < 4) {
          // D3a: add ticket lookup tables (status + type)
          await m.createTable(ticketStatuses);
          await m.createTable(ticketTypes);
        }
        if (from < 5) {
          // Notifications: add cache table for notification center
          await m.createTable(appNotifications);
        }
        if (from < 6) {
          // Backend ADR-0009: assignment moved off the Schedules row into its own table.
          // teamLeadId/staffIds/squadraId stopped arriving from the server, so they are
          // dropped rather than left to sit null forever.
          await m.createTable(scheduleAssignees);
          // TableMigration is Drift's supported way to drop a column from SQLite (which has no
          // DROP COLUMN for this case) — it recreates the table from the current definition and
          // copies the rows across. Flagged experimental for API stability, not correctness, and
          // there is no non-experimental alternative short of leaving the dead columns in place.
          // ignore: experimental_member_use
          await m.alterTable(TableMigration(schedules));
        }
        if (from < 7) {
          // Cantiere timbra: add cantiere_punches table for local-first
          // clock-in/out (mirrors work_sessions for the simple timbra flow).
          await m.createTable(cantierePunches);
        }
        if (from < 8) {
          // Offline-first ticket creation: local outbox so a new ticket
          // typed while offline is never silently discarded.
          await m.createTable(pendingTickets);
        }
        if (from < 9) {
          // Rapportino staff step: mirror the tenant's users so a colleague can be
          // picked offline instead of having their user id typed in by hand.
          await m.createTable(colleagues);
        }
        if (from < 10) {
          // B-05: cache entitlements so feature gating survives loss of signal.
          await m.createTable(entitlements);
        }
        if (from < 11) {
          // AI provenance: whether a model wrote any of a draft's text. Defaults to false, which
          // is the honest answer for every rapportino that predates the column.
          await m.addColumn(draftReports, draftReports.isAiAssisted);
        }
        if (from < 12) {
          // The ticket's display number, which the server has been sending all along.
          //
          // Adding the column is not enough on its own: existing rows are null, and the delta
          // cursor means an unchanged ticket is never sent again — so on every device already in
          // the field the number would stay null forever and the UI would keep falling back to a
          // GUID fragment. `syncCursorGeneration` is bumped alongside this for that reason. A new
          // column on a delta-synced table always needs both.
          await m.addColumn(tickets, tickets.numero);
        }
        if (from < 13) {
          // Suspended/canceled tenants keep read access but every write 403s — the app must be
          // able to say why instead of showing an unexplained failure, so subscription status is
          // now cached alongside the rest of the entitlement.
          await m.addColumn(entitlements, entitlements.subscriptionStatus);
        }
        if (from < 14) {
          // Rapportino autosave was packing GPS/free-text metadata into `details` — the same
          // column that holds the technician's actual typed description — silently overwriting
          // it on every keystroke. Splitting metadata into its own column stops the collision;
          // see the doc comment on `DraftReports.metadataJson`.
          await m.addColumn(draftReports, draftReports.metadataJson);
        }
        if (from < 15) {
          // The mobile ticket creation form had no priority field at all — every ticket created
          // from a phone landed at the backend's implicit default with no way to say otherwise.
          await m.addColumn(pendingTickets, pendingTickets.priorita);
        }
        if (from < 16) {
          // Simple attendance punch always sent GPS as null even when a position was available
          // for free (permission already granted). See `WorkSessions.latitude`/`longitude`.
          await m.addColumn(workSessions, workSessions.latitude);
          await m.addColumn(workSessions, workSessions.longitude);
        }
        if (from < 17) {
          // Cantiere timbra goes offline-first (see cantiere_timbra_sync_service.dart /
          // cantiere_work_log_reconciler.dart): `description` carries the one rich field the
          // offline batch endpoint accepts, `notes` mirrors `WorkSessions.notes`'s
          // reconciliation marker. Device-reported GPS accuracy was captured and discarded on
          // every punch; `WorkSessions.gpsAccuracyMeters` stops throwing it away.
          await m.addColumn(cantierePunches, cantierePunches.description);
          await m.addColumn(cantierePunches, cantierePunches.notes);
          await m.addColumn(workSessions, workSessions.gpsAccuracyMeters);
        }
        if (from < 18) {
          // Ticket detail's Allegati tab gained upload (camera/gallery), and a technician on
          // site cannot be relied on to have signal. Same offline-outbox shape as pendingTickets:
          // see PendingTicketAttachments' own doc comment for why its retry policy is stricter.
          await m.createTable(pendingTicketAttachments);
        }
        if (from < 19) {
          // Offline cache for the rapportino Controlli checklist — see
          // `CachedTicketControls`'s own doc comment.
          await m.createTable(cachedTicketControls);
        }
        if (from < 20) {
          // Vetro (module #2, Tickets): the list/detail redesign needs priority and due date to
          // triage a ticket without opening it — both already arrive over the wire (sync returns
          // the `Ticket` entity itself, same as `numero` before it), just never parsed or stored.
          // Same two-part fix as `numero` (schema 12): the column alone leaves every ticket that
          // predates this migration permanently null, because a delta sync only re-sends rows that
          // changed — see `syncCursorGeneration`'s own doc comment, bumped to v4 alongside this.
          await m.addColumn(tickets, tickets.priority);
          await m.addColumn(tickets, tickets.dueDate);
        }
        if (from < 21) {
          // See `DraftReports.cantiereId`'s own doc comment — this was client-only state that
          // never had anywhere to persist to. No syncCursorGeneration bump needed: this column is
          // authored locally by the mobile client, never delta-synced from the server.
          await m.addColumn(draftReports, draftReports.cantiereId);
        }
        if (from < 22) {
          // Barcode scan-to-lookup for the materiali catalog — see MaterialeBarcodes' own doc
          // comment. Unlike schema 21's cantiereId (client-authored, no server rows to backfill),
          // MaterialeBarcode rows already exist on the backend for materials a device may have
          // synced long ago — a delta sync past an old cursor would only pick up barcodes updated
          // after this point forward, never backfilling the rest. Same reasoning as tickets.numero
          // (schema 12) / tickets.priority (schema 20): syncCursorGeneration bumped to v5 below.
          await m.createTable(materialeBarcodes);
        }
        if (from < 23) {
          // Ticket<->Cantiere link — see Tickets.cantiereId's own doc comment. Same reasoning as
          // schema 20 (tickets.priority/dueDate): already on the wire, needs syncCursorGeneration
          // bumped below or an already-synced device never backfills it.
          await m.addColumn(tickets, tickets.cantiereId);
        }
        if (from < 24) {
          // Fabbisogno offline mirror — see TicketMateriali's own doc comment. New table, not a
          // column, but the same delta blind spot as materiale_barcodes (schema 22): existing
          // TicketMateriale rows on the backend would never backfill for a device whose cursor is
          // already past the owning ticket's last change — syncCursorGeneration bumped below.
          await m.createTable(ticketMateriali);
        }
        if (from < 25) {
          // Every signature now carries GPS + a capture timestamp (mobile: this schema bump;
          // backend: matching `capturedLatitude`/`capturedLongitude`/`capturedAt` upload fields).
          // Nullable — GPS must never block signature capture — so a denied/unavailable position
          // stores null rather than failing the save. Client-authored only, never delta-synced:
          // no syncCursorGeneration bump needed.
          await m.addColumn(reportAllegati, reportAllegati.capturedLatitude);
          await m.addColumn(reportAllegati, reportAllegati.capturedLongitude);
          await m.addColumn(reportAllegati, reportAllegati.capturedAt);
        }
        if (from < 26) {
          // See DraftReports.technicianSignaturePrefillSuppressed's own doc comment. Client-
          // authored only (set locally by Cancella, read locally by the pre-fill guard), never
          // delta-synced: no syncCursorGeneration bump needed.
          await m.addColumn(draftReports, draftReports.technicianSignaturePrefillSuppressed);
        }
        if (from < 27) {
          // Backend's ControlTypeEnum gained a Number type (was only Checkbox/Text/DateTime/
          // TrueFalse/Options) — see ReportControlli.numberValue's own doc comment. Additive and
          // nullable, so a draft saved before this column existed just reads null for it, same
          // as every other addColumn migration above.
          await m.addColumn(reportControlli, reportControlli.numberValue);
        }
        if (from < 28) {
          // Client-side geocode cache for the cantiere detail screen's embedded map — see
          // Cantieri.latitude/longitude's own doc comment. Client-authored only (never sent by
          // the backend, which has no lat/lng on Cantiere at all): no syncCursorGeneration bump
          // needed, same reasoning as schema 21/25/26's own client-authored columns.
          await m.addColumn(cantieri, cantieri.latitude);
          await m.addColumn(cantieri, cantieri.longitude);
        }
        if (from < 29) {
          // Effective clock-in method (tenant default + per-user override), mirrored from /auth/me
          // the same way every other entitlement field already is.
          await m.addColumn(entitlements, entitlements.clockInMethod);
        }
        if (from < 30) {
          // "Da tornare" — see DraftReports.richiedeSecondoIntervento's own doc comment.
          // Client-authored only (set locally on the Riepilogo step, read locally to build the
          // submit payload), never delta-synced: no syncCursorGeneration bump needed, same
          // reasoning as schema 21/25/26/28's own client-authored columns.
          await m.addColumn(draftReports, draftReports.richiedeSecondoIntervento);
        }
        if (from < 31) {
          // Confirmed-deactivation signal — see Entitlements.isAccountDeactivated's own doc
          // comment. Defaults to false, the honest answer for every row written before this
          // column existed.
          await m.addColumn(entitlements, entitlements.isAccountDeactivated);
        }
        if (from < 32) {
          // Tags field-parity gap — see Tickets.tagsJson's own doc comment. Already on the wire
          // (Ticket.Tags), same delta blind spot as schema 20/23's tickets columns: a delta sync
          // only re-sends rows that changed, so syncCursorGeneration bumped below.
          await m.addColumn(tickets, tickets.tagsJson);
        }
        if (from < 33) {
          // Field-parity gap on the CREATE path — PendingTickets.dueDate/technicianNotes/agentId/
          // tagsJson, so a ticket queued offline (or created online through the same queue) can
          // carry the same fields the edit path already gained in schema 32. Client-authored, same
          // as every other PendingTickets column — no syncCursorGeneration bump needed.
          await m.addColumn(pendingTickets, pendingTickets.dueDate);
          await m.addColumn(pendingTickets, pendingTickets.technicianNotes);
          await m.addColumn(pendingTickets, pendingTickets.agentId);
          await m.addColumn(pendingTickets, pendingTickets.tagsJson);
        }
        if (from < 34) {
          // Report-submit retry bookkeeping — see DraftReports.submissionAttempts's own doc
          // comment. Client-authored only (never delta-synced): no syncCursorGeneration bump.
          // Both default to "no attempts, not transient", the honest answer for every row
          // written before this.
          await m.addColumn(draftReports, draftReports.submissionAttempts);
          await m.addColumn(draftReports, draftReports.submissionErrorTransient);
          // Rows already `failed` were stuck by the old firma-* 404 bug (signatures POSTed
          // before the report existed). Flag them transient so the next startup flush retries
          // them once the fixed client is in place — bounded by the queue's retry cap.
          await customStatement(
            'UPDATE draft_reports SET submission_error_transient = 1 '
            "WHERE submission_state = 'failed'",
          );
        }
        if (from < 35) {
          // Diagnosi / Soluzione on the rapportino — see DraftReports.diagnosi's own doc comment.
          // Already on the wire (Report entity in the sync payload), but only Bozza headers sync
          // down and a Bozza opened for editing is re-imported in full (importServerReport), so
          // no syncCursorGeneration bump is needed. Null for every row written before this.
          await m.addColumn(draftReports, draftReports.diagnosi);
          await m.addColumn(draftReports, draftReports.soluzione);
        }
        if (from < 36) {
          // Per-asset checklists, strumenti and structured submit problems — see the table docs
          // above. New tables and client-authored columns only: nothing here is backfilled from the
          // existing rows, and the delta cursor is bumped to v9 in SyncService's task so a device
          // that was already synced receives the checklist members once.
          await m.createTable(controlGroups);
          await m.createTable(ticketControls);
          await m.createTable(ticketAssets);
          await m.createTable(assets);
          await m.createTable(strumenti);
          await m.createTable(reportStrumenti);
          await m.createTable(checklistOmittedTickets);
          await m.addColumn(reportControlli, reportControlli.note);
          await m.addColumn(draftReports, draftReports.strumentiPrefilled);
          await m.addColumn(draftReports, draftReports.submissionProblemJson);
          await _createChecklistIndexes();
        }
        if (from < 37) {
          // The reference mirror the ticket wizard needs offline, plus the queue columns that let a
          // created ticket carry them. New tables and client-authored columns: nothing is backfilled
          // and the delta cursor is NOT bumped — the reference queries carry no delta, so a device
          // receives them on its next ordinary sync. See this file's schema-33 step for the same
          // reasoning about client-authored columns.
          await m.createTable(contracts);
          await m.createTable(commesse);
          await m.createTable(prodottiAssistenza);
          await m.createTable(agents);
          // A separate helper, deliberately not folded into _createChecklistIndexes: that one runs
          // from the `from < 36` branch too, where these tables do not exist yet.
          await _createReferenceIndexes();

          await m.addColumn(pendingTickets, pendingTickets.contractId);
          await m.addColumn(pendingTickets, pendingTickets.commessaId);
          await m.addColumn(pendingTickets, pendingTickets.cantiereId);
          await m.addColumn(pendingTickets, pendingTickets.prodottoAssistenzaIdsJson);
          await m.addColumn(pendingTickets, pendingTickets.repairableField);
        }
        if (from < 38) {
          // `dueDate` becomes a civil date stored as `yyyy-MM-dd` TEXT on both tables — see
          // `Tickets.dueDate`'s own doc comment for the bug and `Strumenti.calibrationExpiry`'s for
          // the precedent. This is not an `addColumn` step: the two columns already exist as INTEGER
          // epoch seconds, SQLite has no ALTER COLUMN TYPE, and a plain copy would carry the number
          // straight into a TEXT column (where the affinity would render it as "1759536000").
          //
          // `alterTable` is Drift's supported way to change a column's type: it re-creates the table
          // from the current definition and copies the rows across, and `columnTransformer` is the
          // hook that rewrites the values on the way. What is being rewritten is an epoch second
          // count of whatever moment the old column stored, and which moment that is depends on who
          // wrote the row — see [_civilDayOfDueDate] for which day each of them means.
          //
          // No `syncCursorGeneration` bump: unlike schema 12/20/23/32, nothing has to be refetched —
          // the rows the device already holds are rewritten in place, and a full sync would only
          // re-deliver the same dates.
          await m.alterTable(
            // ignore: experimental_member_use
            TableMigration(
              tickets,
              // `extensionValues` (schema 46) is declared above but absent from a 37-or-older
              // `tickets`, and this re-creation copies with a statement built from the CURRENT
              // definition — see the `pendingTickets` migration below for the mechanism and why an
              // unnamed absent column comes out holding its own name. Here that would leave every
              // such ticket with the literal string "extension_values", which `decodeExtensionValues`
              // reads as "no values recorded", so nothing would ever surface it. It is the first
              // `tickets` column to need this.
              newColumns: [tickets.extensionValues],
              columnTransformer: {
                tickets.dueDate: CustomExpression<String>(_civilDayOfDueDate('tickets')),
              },
            ),
          );
          await m.alterTable(
            // ignore: experimental_member_use
            TableMigration(
              pendingTickets,
              // The columns this 37-or-older table does NOT have, even though the class above
              // declares them. Not bookkeeping: `TableMigration` copies the rows with a statement
              // built from the CURRENT definition — `INSERT INTO tmp_for_copy_pending_tickets
              // (<every column>) SELECT <every column> FROM pending_tickets` — skipping only the
              // columns named here (or given a `columnTransformer`). A column it copies but the old
              // table lacks is read back as a bare quoted identifier, and SQLite resolves an unknown
              // double-quoted identifier as a string LITERAL rather than failing the way an unquoted
              // one would, so every row would silently come out holding the column's own name:
              // a value the server refuses with a 400, which carries no `field` and so can never be
              // classified repairable — that row would retry forever. Naming it here leaves the new
              // table's own default (NULL, "let the server resolve it from type/contract").
              //
              // Standing rule for this step: every column `tickets` or `pendingTickets` gains after
              // schema 37 belongs in `newColumns` — here for `pendingTickets`, and in the `tickets`
              // migration above for `tickets.extensionValues` (schema 46). Those two are the whole
              // list so far.
              newColumns: [pendingTickets.maintenanceTemplateId],
              columnTransformer: {
                pendingTickets.dueDate: CustomExpression<String>(
                  _civilDayOfDueDate('pending_tickets'),
                ),
              },
            ),
          );
        }
        if (from < 39) {
          // Stale-submit guard: the report row's version the phone last saw, carried from the
          // import/cantiere-create fetch to `POST /api/reports/submit`. A plain nullable column —
          // every pre-existing row is left null, which reads as "never on the server" and makes the
          // server skip the check, exactly the old behaviour, so no backfill is possible or wanted
          // (the device genuinely does not know those versions and must not invent one).
          await m.addColumn(draftReports, draftReports.expectedVersion);
        }
        if (from < 40) {
          // The maintenance-template catalogue the ticket wizard's "Modello checklist" picker reads
          // offline, and the pending-ticket column the wizard's choice is queued into.
          //
          // A new table plus a new nullable column, and NO `syncCursorGeneration` bump: unlike a
          // since-filtered ticket list (which is why schema 36's checklist tables needed v9), the
          // template catalogue travels in full on every sync with no delta filter, so there is no
          // row a delta cursor could leave unbackfilled — `_replaceMaintenanceTemplates` fills it the
          // next time the device syncs at all.
          await m.createTable(maintenanceTemplates);
          // The column is added only when the table really lacks it. A device upgrading from 37 or
          // older ALREADY has it: the `from < 38` step above re-creates `pending_tickets` from the
          // CURRENT table definition — which now declares `maintenanceTemplateId` — so by the time
          // this step runs the column exists and an unconditional `addColumn` dies on `duplicate
          // column name` before the app ever opens. Devices coming from 38 or 39 have the old table
          // shape and do need the add. Ask SQLite which of the two this upgrade is instead of
          // inferring it from `from`.
          //
          // This guard only prevents the crash, not the wrong data: skipping the add is correct only
          // because step 38 declares the column as a new one, so the re-created table holds NULL
          // rather than the literal column name its copy would otherwise read out of the old table.
          // The two changes belong together — one without the other leaves a ≤37 device either
          // crashing on open or holding a template id that can never be sent.
          if (!await _columnExists(m.database, 'pending_tickets', 'maintenance_template_id')) {
            await m.addColumn(pendingTickets, pendingTickets.maintenanceTemplateId);
          }
        }
        if (from < 41) {
          // Per-instrument free text on a rapportino ("how it was used", "esito"). Two nullable
          // columns, no backfill: every existing row simply has no note.
          //
          // Guarded by `PRAGMA table_info`, not by `from`: a device coming from 35 or older gets
          // `report_strumenti` created by the `from < 36` step from the CURRENT definition, which
          // already declares both columns, and an unconditional `addColumn` would die on
          // `duplicate column name` before the app opens.
          if (!await _columnExists(m.database, 'report_strumenti', 'usage_description')) {
            await m.addColumn(reportStrumenti, reportStrumenti.usageDescription);
          }
          if (!await _columnExists(m.database, 'report_strumenti', 'outcome')) {
            await m.addColumn(reportStrumenti, reportStrumenti.outcome);
          }
        }
        if (from < 42) {
          // The customer's agent, which pre-fills a new ticket's Riferimento. Nullable, no backfill
          // here: the value is already on the wire (`customers[].agentId`), so the cursor bump below
          // (v10) is what makes every existing device re-download its customers and fill the column.
          //
          // Guarded by `PRAGMA table_info`, not by `from`, like the steps above: `customers` is never
          // re-created from the current definition by an earlier step today, but the guard costs
          // nothing and an `alterTable` added later would turn an unconditional add into a crash on
          // `duplicate column name` before the app opens.
          if (!await _columnExists(m.database, 'customers', 'agent_id')) {
            await m.addColumn(customers, customers.agentId);
          }
        }
        if (from < 43) {
          // The cantiere crew mirror — who is assigned to a cantiere and which of them is lead — so
          // the lead-only clock-in affordances and the teammate picker survive offline (the
          // cantiere punches themselves already queue offline; the crew was the last live-only read
          // in that flow).
          //
          // A new client-only table, and NO `syncCursorGeneration` bump, for the same reason schema
          // 40 needed none: the sync member carries the *complete* crew of every cantiere the
          // payload already carries, with no delta filter on the crew rows (a lead change must reach
          // the device even when the cantiere row itself is unchanged). So there is no row a delta
          // cursor could leave unbackfilled — the next ordinary sync fills this table. Nothing is
          // backfilled here: the device genuinely holds no crew until that sync, and inventing one
          // would make `isLeadForCantiereProvider` lie.
          await m.createTable(cantiereCrewAssignments);
          await _createCantiereCrewIndexes();
        }
        if (from < 44) {
          // The two attachment columns the sync now delivers: what kind of file it is, and the
          // SHA-256 of its bytes. Both nullable/defaulted, so no backfill here — every device
          // fills them by downloading the attachment list once, which it does on the next sync
          // whatever its cursor (the list travels whole, like the maintenance catalogue).
          //
          // Guarded by `PRAGMA table_info` rather than by `from`, like the steps above: no earlier
          // step re-creates `report_allegati` from the current definition today, but the guard is
          // what keeps an `alterTable` added later from turning this into a crash on `duplicate
          // column name` before the app opens.
          //
          // 44, not 43: 43 is already the cantiere-crew step on `main`, and a device that ran that
          // build must still get these two columns.
          if (!await _columnExists(m.database, 'report_allegati', 'kind')) {
            await m.addColumn(reportAllegati, reportAllegati.kind);
          }
          if (!await _columnExists(m.database, 'report_allegati', 'content_hash')) {
            await m.addColumn(reportAllegati, reportAllegati.contentHash);
          }
        }
        if (from < 45) {
          // Ticket timers: a technician on site could read a ticket but not book a minute of work
          // against it without a network. The mirror also holds rows the device starts offline
          // until the batch upsert accepts them.
          //
          // 45, not 44: 44 is already the report-allegati step once this stacks on O-8b/O-8c, and
          // a device that ran a build of that step must still get this table.
          await m.createTable(ticketTimers);
        }
        if (from < 46) {
          // Tenant extension fields ("campi aggiuntivi"), the last live-only read on the
          // rapportino and cantiere forms: the *definitions* section vanished offline, and the
          // *values* were already on the wire inside the entity JSON but had nowhere to land.
          //
          // The definitions table is filled by the very next sync whatever its cursor (that member
          // travels whole, like the maintenance catalogue), so it needs no backfill here. The three
          // `extension_values` columns are the opposite case — a delta sync only re-sends rows that
          // changed, so an unedited ticket would keep a null forever — which is why
          // `syncCursorGeneration` is bumped to v12 alongside this step.
          //
          // Guarded by `PRAGMA table_info` rather than by `from`, like the steps above: no earlier
          // step re-creates `tickets`/`cantieri`/`draft_reports` from the current definition today,
          // but the guard is what keeps an `alterTable` added later from turning this into a crash
          // on `duplicate column name` before the app opens.
          await m.createTable(extensionFieldDefinitions);
          if (!await _columnExists(m.database, 'tickets', 'extension_values')) {
            await m.addColumn(tickets, tickets.extensionValues);
          }
          if (!await _columnExists(m.database, 'cantieri', 'extension_values')) {
            await m.addColumn(cantieri, cantieri.extensionValues);
          }
          if (!await _columnExists(m.database, 'draft_reports', 'extension_values')) {
            await m.addColumn(draftReports, draftReports.extensionValues);
          }
        }
        if (from < 47) {
          // The warehouses a rapportino material line can be sourced from. A brand-new table, so
          // it needs no backfill: the member travels whole on every sync (never delta-filtered),
          // which fills the mirror on the very next one whatever its cursor. No cursor-generation
          // bump is needed for the same reason — unlike a new column on a delta-synced table.
          await m.createTable(magazzini);
        }
        if (from < 48) {
          // The customer's fiscal identity and mobile number, already on the wire inside the
          // customer entity: the "Dati fiscali" card could show only P.IVA, and its own comment
          // called SDI/PEC/Codice Fiscale out as a real gap. A technician opening a customer on
          // site had no way to read the customer's CF or the mobile number.
          //
          // Needs the cursor bump to v13: the `fullScope` (office) branch delta-filters customers,
          // so an unedited customer would keep these null forever. The technician branch sends its
          // customers whole every sync and would have filled them anyway.
          //
          // Guarded by `PRAGMA table_info` rather than by `from`, like the steps above: no earlier
          // step re-creates `customers` from the current definition today, but the guard is what
          // keeps an `alterTable` added later from turning this into a crash on `duplicate column
          // name` before the app opens.
          if (!await _columnExists(m.database, 'customers', 'cellulare')) {
            await m.addColumn(customers, customers.cellulare);
          }
          if (!await _columnExists(m.database, 'customers', 'fiscal_code')) {
            await m.addColumn(customers, customers.fiscalCode);
          }
          if (!await _columnExists(m.database, 'customers', 'sdi_code')) {
            await m.addColumn(customers, customers.sdiCode);
          }
          if (!await _columnExists(m.database, 'customers', 'pec')) {
            await m.addColumn(customers, customers.pec);
          }
          if (!await _columnExists(m.database, 'customers', 'province')) {
            await m.addColumn(customers, customers.province);
          }
        }
        if (from < 49) {
          // Customer contacts, the last live-only read on the customer screen: its Contatti
          // section called `GET /api/customers/{id}/contacts` on every open and rendered an error
          // card offline, which is exactly where a technician needs a phone number.
          //
          // A brand-new table, so nothing to backfill. The cursor moves to v14 alongside it: on the
          // office branch customers are delta-filtered, so a device whose cursor is already past a
          // customer would never receive its contacts until something else edited that customer.
          await m.createTable(customerContacts);
          await _createCustomerContactIndexes();
        }
        if (from < 50) {
          // Whose instrument it is, so the rapportino picker can say "di Anna Neri" instead of
          // offering a bare name the technician has to guess the owner of. The name travels from
          // the server rather than being resolved from the colleague mirror, which carries active
          // users only — an instrument stays with someone who has since been deactivated until the
          // office reassigns it.
          //
          // Nothing to backfill and no cursor bump: `strumenti` is one of the members that travel
          // WHOLE on every sync (`replaceStrumenti` deletes and re-inserts), so the next sync fills
          // these columns whatever its cursor.
          //
          // Guarded by `PRAGMA table_info` rather than by `from`, like the steps above: no earlier
          // step re-creates `strumenti` from the current definition today, but the guard is what
          // keeps an `alterTable` added later from turning this into a crash on `duplicate column
          // name` before the app opens.
          if (!await _columnExists(m.database, 'strumenti', 'holder_user_id')) {
            await m.addColumn(strumenti, strumenti.holderUserId);
          }
          if (!await _columnExists(m.database, 'strumenti', 'holder_name')) {
            await m.addColumn(strumenti, strumenti.holderName);
          }

          // The cantiere clock-out screen's own fields: the description typed on leaving, the
          // safety note, and the departure fix. They went to the server only through the online
          // `end` call — a technician who clocked out with no signal lost all three, and the batch
          // upsert the queue drains through had nowhere to put them.
          //
          // Guarded by `PRAGMA table_info` rather than by `from`, like the steps above: no earlier
          // step re-creates `cantiere_punches` from the current definition today, but the guard is
          // what keeps an `alterTable` added later from turning this into a crash on `duplicate
          // column name` before the app opens.
          if (!await _columnExists(m.database, 'cantiere_punches', 'safety_notes')) {
            await m.addColumn(cantierePunches, cantierePunches.safetyNotes);
          }
          if (!await _columnExists(m.database, 'cantiere_punches', 'departure_latitude')) {
            await m.addColumn(cantierePunches, cantierePunches.departureLatitude);
          }
          if (!await _columnExists(m.database, 'cantiere_punches', 'departure_longitude')) {
            await m.addColumn(cantierePunches, cantierePunches.departureLongitude);
          }
        }
        if (from < 51) {
          // The cantiere clock-in screen's rich fields, the counterpart of schema 50's clock-out
          // set: the work order, the equipment used, the crew size and the weather. They reached
          // the server only through the online `start` call, so an offline clock-in arrived with
          // none of them — silently, since nothing on the device asked again.
          //
          // Same `PRAGMA table_info` guard as 50, for the same reason: a device that already
          // carries one of these columns must not die on `duplicate column name` before the app
          // opens.
          if (!await _columnExists(m.database, 'cantiere_punches', 'work_order_number')) {
            await m.addColumn(cantierePunches, cantierePunches.workOrderNumber);
          }
          if (!await _columnExists(m.database, 'cantiere_punches', 'equipment_used')) {
            await m.addColumn(cantierePunches, cantierePunches.equipmentUsed);
          }
          if (!await _columnExists(m.database, 'cantiere_punches', 'team_size')) {
            await m.addColumn(cantierePunches, cantierePunches.teamSize);
          }
          if (!await _columnExists(m.database, 'cantiere_punches', 'weather_conditions')) {
            await m.addColumn(cantierePunches, cantierePunches.weatherConditions);
          }
        }
      },
    );
  }

  /// The `columnTransformer` expression that rewrites one INTEGER `due_date` column (schema 37 and
  /// older) into the `yyyy-MM-dd` label of the day it was meant to mean.
  ///
  /// The old column is Drift's `DateTimeColumn`: an epoch second count of *some* moment. Which
  /// moment, and therefore which calendar day it stands for, depends on who wrote the row:
  ///
  ///   - the sync writes the server's copy of the ticket, and the API serializes `Ticket.DueDate`
  ///     as `…T00:00:00Z` — a UTC midnight, whose day is its day in UTC. (This is also the shape
  ///     the backend reads back: its `UtcDateTimeConverter` treats an unspecified kind as UTC.)
  ///   - `showDatePicker` returns a *local* midnight, and the wizard and the edit screen both store
  ///     that value as-is — its day is its day in the device's own zone. These are the rows the old
  ///     code displayed *correctly*; only the server's came out a day early west of UTC, which is
  ///     the bug the whole change exists to remove.
  ///
  /// So neither conversion alone is right. `unixepoch` on its own drags every picker-set date back
  /// one day on any device east of UTC — every Italian device, i.e. every device that actually
  /// holds rows — and that is the one error this migration must not make, because it would rewrite
  /// dates a technician chose into dates they did not, with nothing left to notice it. `localtime`
  /// on its own is right for exactly those rows but freezes the off-by-one on the server's, which
  /// the next delta sync would not correct for tickets nobody edits.
  ///
  /// Both branches read the column through `unixepoch` first: without that modifier SQLite reads a
  /// bare number as a *Julian day*, and an epoch second count is far outside that range — it returns
  /// `2000-01-01` for every row rather than raising, so the mistake is silent and total.
  ///
  /// The `CASE` tells the two apart by the only signal the column carries: whether the stored
  /// instant *is* a UTC midnight, which is the server's shape and nothing a picker produces unless
  /// the device itself runs at UTC (where the two days coincide anyway). A NULL stays NULL through
  /// both branches, so a ticket with no due date keeps none.
  static String _civilDayOfDueDate(String table) =>
      "CASE WHEN strftime('%H:%M:%S', $table.due_date, 'unixepoch') = '00:00:00' "
      "THEN strftime('%Y-%m-%d', $table.due_date, 'unixepoch') "
      "ELSE strftime('%Y-%m-%d', $table.due_date, 'unixepoch', 'localtime') END";

  /// Whether [table] currently carries [column], asked of SQLite rather than assumed.
  ///
  /// A migration step that adds a column cannot always trust `from`: an earlier `alterTable` step
  /// re-creates its table from the CURRENT definition, so a column declared after that step exists
  /// already on any device the re-creation ran for. `Migrator.addColumn` does not emit
  /// `IF NOT EXISTS` — it dies on `duplicate column name` — so the only correct answer is to look.
  /// Used by the schema-40 step for `pending_tickets.maintenance_template_id`.
  static Future<bool> _columnExists(
    DatabaseConnectionUser db,
    String table,
    String column,
  ) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  // ── sync_meta helpers ────────────────────────────────────────────────────

  /// Which generation of the sync cursor this build understands.
  ///
  /// Bumping it makes every existing device do one full sync instead of a delta, and it exists
  /// because a delta cursor can outlive its own correctness. It did: the server's delta filter
  /// compared `UpdatedAt > since` against rows whose `UpdatedAt` is null until someone edits
  /// them, so anything created after a device's last sync was invisible to that device forever.
  /// Fixing the server does not help a phone whose cursor is already past those rows — it will
  /// never ask for them again. Only a full sync recovers, and the technician cannot be asked to
  /// reinstall the app.
  ///
  /// Implemented as part of the row id rather than a new column so it needs no schema migration:
  /// a device on an older generation simply finds no row and syncs from scratch.
  ///
  /// v2 — 2026-08-16, the COALESCE(UpdatedAt, CreatedAt) delta fix.
  /// v3 — 2026-08-17, schema 12 added `tickets.numero`. The column arrives empty and a delta sync
  ///      would never refill it, because the tickets it needs are precisely the ones that have not
  ///      changed. Same reasoning as v2: a cursor can outlive its own correctness.
  /// v4 — 2026-08-26, schema 20 added `tickets.priority`/`tickets.dueDate`. Same reasoning as v3.
  /// v5 — 2026-08-27, schema 22 added `materiale_barcodes` (new table, not a column, but the
  ///      same delta blind spot: existing MaterialeBarcode rows on the backend would never
  ///      backfill for a device whose cursor is already past their (unrelated) last change).
  /// v6 — 2026-08-31, schema 23 added `tickets.cantiereId`. Same reasoning as v4
  ///      (tickets.priority/dueDate): already on the wire, a delta sync would never refill it for
  ///      tickets that haven't otherwise changed.
  /// v7 — 2026-08-31, schema 24 added `ticket_materiali` (new table, same delta blind spot as v5's
  ///      `materiale_barcodes`).
  /// v8 — 2026-09-24, schema 32 added `tickets.tagsJson`. Same reasoning as v4/v6: already on the
  ///      wire, a delta sync would never refill it for tickets that haven't otherwise changed.
  /// v9 — 2026-10-07, schema 36 added the per-asset checklist tables. A technician's checklist is
  ///      resent on every sync, but a fullScope caller's ticket list is since-filtered, so a device
  ///      whose cursor is already past a ticket would never receive its asset rows. Same reasoning
  ///      as v3-v8.
  /// v10 — 2026-10-16, schema 42 added `customers.agentId`. Already on the wire, and a delta sync only
  ///      re-sends customers that changed, so an unedited customer would keep a null agent — and the
  ///      new-ticket pre-fill silently never fire for it — until somebody happened to edit it.
  /// v11 — 2026-10-21, the sync-v2 authoritative scope. Two independent reasons, both about a
  ///      cursor this device already holds:
  ///      * the server now hands back a cursor with a short overlap, so a row written while the
  ///        request was running is re-read next time instead of falling behind the cursor
  ///        forever. A cursor written by v10 or earlier predates that overlap and would never
  ///        re-request those rows.
  ///      * the mirror now PRUNES to the payload's authoritative `scope`, and a prune is only
  ///        safe against a complete payload. Resuming from a stale delta cursor would treat rows
  ///        a delta merely did not mention as out of scope and delete them.
  /// v12 — 2026-10-21, schema 46 added `tickets`/`cantieri`/`draft_reports.extensionValues`. Same
  ///      reasoning as v3/v4/v6/v8: the values were already on the wire inside the entity JSON, and a
  ///      delta sync only re-sends rows that changed, so an unedited entity would keep a null
  ///      forever. The definitions table added by the same step needs no bump — its member travels
  ///      whole on every sync.
  /// v13 — 2026-10-22, schema 48 added the customer's fiscal identity (`fiscalCode`, `sdiCode`,
  ///      `pec`, `province`) and `cellulare`. Same reasoning as v10's `customers.agentId`: the
  ///      values were already on the wire, and a delta sync only re-sends customers that changed,
  ///      so an unedited customer would keep them null forever — on the office branch that reads
  ///      the tenant's whole book delta-filtered.
  /// v14 — 2026-10-22, schema 49 added `customer_contacts`. A new table, but the same blind spot
  ///      as v10: on the office branch customers are delta-filtered, so a device whose cursor is
  ///      already past a customer would never receive its contacts until something else touched
  ///      that customer — and the Contatti section would stay empty on a device that had just been
  ///      upgraded to show it.
  static const String syncCursorGeneration = 'v14';

  static const String _cursorId = 'default:$syncCursorGeneration';

  /// Indexes the checklist read paths need (a ticket's rows, one asset's rows, a report's
  /// instruments). Plain statements: Drift's `createTable` does not create indexes, and
  /// `IF NOT EXISTS` keeps `onCreate` and `onUpgrade` idempotent.
  Future<void> _createChecklistIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ticket_controls_ticket ON ticket_controls (ticket_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS ticket_controls_asset '
      'ON ticket_controls (ticket_id, prodotto_assistenza_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS report_strumenti_report ON report_strumenti (report_id)',
    );
  }

  /// Indexes the reference pickers read by: every one of them is "the rows for this customer".
  ///
  /// Kept separate from [_createChecklistIndexes] on purpose: that helper is also called from the
  /// `from < 36` branch, where `contracts`/`commesse`/`prodotti_assistenza` do not exist yet, so a
  /// `CREATE INDEX ... ON contracts` there would fail the upgrade for any device older than 36.
  /// `IF NOT EXISTS` keeps this idempotent (a fresh install runs it from `onCreate`, an upgrade
  /// from the `from < 37` branch).
  Future<void> _createReferenceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS contracts_customer ON contracts (customer_id, is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS commesse_customer ON commesse (customer_id, is_active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS prodotti_assistenza_customer '
      'ON prodotti_assistenza (customer_id, is_active)',
    );
  }

  /// The crew mirror is only ever read as "the rows for this cantiere", by the teammate picker and
  /// by the lead derivation in cantiere_timbra_screen.dart.
  ///
  /// Kept separate from the other index helpers for the same reason [_createReferenceIndexes] is
  /// kept from [_createChecklistIndexes]: the table it indexes does not exist on devices older than
  /// schema 43, and a `CREATE INDEX ... ON cantiere_crew_assignments` emitted from an earlier
  /// branch would fail their upgrade. `IF NOT EXISTS` keeps this idempotent (a fresh install runs
  /// it from `onCreate`, an upgrade from the `from < 43` branch).
  Future<void> _createCantiereCrewIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS cantiere_crew_assignments_cantiere '
      'ON cantiere_crew_assignments (cantiere_id)',
    );
  }

  /// The contact mirror is only ever read as "the contacts of this customer".
  ///
  /// Separate from the other index helpers for the same reason they are separate from each other:
  /// the table does not exist on devices older than schema 49, and a `CREATE INDEX ... ON
  /// customer_contacts` emitted from an earlier branch would fail their upgrade.
  Future<void> _createCustomerContactIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS customer_contacts_customer '
      'ON customer_contacts (customer_id)',
    );
  }

  Future<DateTime?> getLastSync() async {
    final row = await (select(syncMeta)..where((t) => t.id.equals(_cursorId))).getSingleOrNull();
    return row?.lastSync;
  }

  /// [getLastSync], but live: emits again whenever [setLastSync] writes a new cursor, so a screen
  /// can show "ultima sincronizzazione" without polling. Emits null until the first successful sync
  /// (there is then no `sync_meta` row at all — the same "never synced" the getter reports).
  Stream<DateTime?> watchLastSync() {
    final query = select(syncMeta)..where((t) => t.id.equals(_cursorId));
    return query.watchSingleOrNull().map((row) => row?.lastSync);
  }

  Future<void> setLastSync(DateTime dt) async {
    await transaction(() async {
      // Drop cursors from older generations on the way past. They are never read again, and
      // leaving one row per shipped generation to accumulate is the kind of thing nobody notices
      // until there are twelve of them.
      await (delete(syncMeta)..where((t) => t.id.equals(_cursorId).not())).go();
      await into(syncMeta).insertOnConflictUpdate(
        SyncMetaCompanion.insert(id: const Value(_cursorId), lastSync: Value(dt)),
      );
    });
  }

  /// Deletes every row from every table — the entire synced/offline dataset for whichever
  /// account was last signed in on this device. Must run on sign-out: this is a shared/rotating-
  /// device field-service app (van tablets, rotating technicians), and without this the next
  /// person to sign in — possibly a different tenant entirely — would see the previous account's
  /// full cached tickets/customers/cantieri/notifications until an eventual sync happened to
  /// overwrite each row (upsert-based sync never clears rows that no longer exist for the new
  /// tenant, so some could persist indefinitely).
  ///
  /// Deletes rows rather than deleting the underlying sqlite file: this connection stays open and
  /// usable immediately afterward (e.g. for a subsequent sign-in on the same app session), with no
  /// risk of racing a file delete against an open native handle.
  Future<void> wipeAllData() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
}

// ── Connection factory ────────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'tasktap.db'));
    return NativeDatabase.createInBackground(file);
  });
}
