// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_rack.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/smart_working/smart_working_request_api_client.dart';
import '../admin/admin_widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// The server's three range rules, verbatim.
//
// Copied word for word from `SmartWorkingRequestService.ValidateRange` (api PR #183) so the two
// cannot drift in the technician's eyes: whether a window is refused by the form or by the server,
// the sentence is the same one. The strings are hard-coded Italian, like every other surface in
// this app — there is no `.arb` in this repo.
// ══════════════════════════════════════════════════════════════════════════════
const String _kSmartWorkingEndBeforeStart = 'La data di fine non può precedere la data di inizio.';
const String _kSmartWorkingRangeTooLong =
    'Il periodo richiesto è troppo lungo (massimo un anno).';
const String _kSmartWorkingBackdated =
    'Non è possibile richiedere smart working per una data passata.';

/// The widest window the server accepts, as a day COUNT between the two civil dates. A difference
/// of exactly 366 is allowed (`> 366` is refused), so this mirrors `DateOnly.DayNumber` arithmetic
/// rather than "one calendar year".
const int _kSmartWorkingMaxSpanDays = 366;

/// New smart-working request. Create-only — `SmartWorkingRequestsController` has no update
/// endpoint (create/list/cancel only), so this never edits an existing row.
///
/// A request is a MARKER for one or more remote days, never hours (see
/// `SmartWorkingRequestApiClient`'s file doc): two civil dates and an optional note, nothing that
/// looks like a timesheet.
class SmartWorkingFormScreen extends ConsumerStatefulWidget {
  const SmartWorkingFormScreen({
    super.key,
    @visibleForTesting this.initialStartDate,
    @visibleForTesting this.initialEndDate,
  });

  /// Test seam only: the production route opens the form on today. The date pickers deliberately
  /// never offer a day the server rejects — the start picker's `firstDate` is today, exactly like
  /// `ferie_permessi_form_screen.dart` — so the backdated branch cannot be reached by tapping
  /// through the UI at all. Seeding the dates here lets the widget tests pin every rule without
  /// driving three date-picker dialogs.
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  @override
  ConsumerState<SmartWorkingFormScreen> createState() => _SmartWorkingFormScreenState();
}

class _SmartWorkingFormScreenState extends ConsumerState<SmartWorkingFormScreen> {
  final _reasonCtrl = TextEditingController();
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isSaving = false;

  /// The civil day this form was opened on, captured once.
  ///
  /// The pickers read a fresh [_today] each time they open, but the submit-time range check uses
  /// THIS value. A form opened at 23:59 and submitted at 00:01 must not suddenly call the window
  /// it was built around "past" — and a test that seeds its dates from the day it started must not
  /// flip on a midnight straddle. A form genuinely left open across midnight is settled by the
  /// server, whose `detail` reaches the technician verbatim (see [_rangeError]).
  ///
  /// Assigned unconditionally in [initState], not as a `late` field initialiser: a `late` field is
  /// forced at its FIRST READ, which is `initState` only when no seeded date is passed — with the
  /// test seam it would be read at submit instead, and "captured at open" would be false in exactly
  /// the case the sentence above exists for.
  late final DateTime _openedOn;

  @override
  void initState() {
    super.initState();
    _openedOn = _today;
    _startDate = _dayOnly(widget.initialStartDate ?? _openedOn);
    _endDate = _dayOnly(widget.initialEndDate ?? _startDate);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  /// The device-local civil day, fresh on every read — never `DateTime.now().toUtc()`. See
  /// [_rangeError]'s doc for why local, not UTC, is the right "today" here.
  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// A picker hands back a local midnight; keep only its y/m/d so comparisons never see a clock.
  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `DateOnly.DayNumber` semantics: a UTC-normalised civil date has no DST hours in it, so the
  /// difference between two of them is an exact day count. Doing this on local midnights would
  /// lose or gain an hour across a DST change and could turn a 366-day window into 365 (or, worse,
  /// let a 367-day one through).
  static DateTime _civil(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Client-side mirror of the server's three range rules, checked in the server's own order.
  ///
  /// Rule 3 is the one rule the client cannot decide exactly, and the handling is deliberate: the
  /// server resolves "today" through the TENANT's configured time zone, which this device has no
  /// way to know. So the comparison below uses the DEVICE-local civil day ([_openedOn]: local
  /// y/m/d — never UTC, never `DateTime.now().toUtc()`), and the server stays the authority: if the
  /// two disagree, in either direction, the server's 400 `detail` is what the technician reads,
  /// verbatim (see `_save`'s `SmartWorkingValidationError` branch). This check is therefore a
  /// courtesy that spares an obvious round trip, not a second source of truth.
  static String? _rangeError({
    required DateTime start,
    required DateTime end,
    required DateTime today,
  }) {
    if (_civil(end).isBefore(_civil(start))) return _kSmartWorkingEndBeforeStart;
    if (_civil(end).difference(_civil(start)).inDays > _kSmartWorkingMaxSpanDays) {
      return _kSmartWorkingRangeTooLong;
    }
    if (_civil(start).isBefore(_civil(today))) return _kSmartWorkingBackdated;
    return null;
  }

  Future<void> _pickStartDate() async {
    final first = _today;
    final last = DateUtils.addDaysToDate(first, _kSmartWorkingMaxSpanDays);
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampToWindow(_startDate, first, last),
      firstDate: first,
      // The server refuses a span over a year — do not offer a start the server rejects.
      lastDate: last,
    );
    // Deliberately NOT auto-correcting `_endDate` when it falls before the new start (ferie's
    // form does, silently moving a date under the technician's finger). Leaving it is what makes
    // the server's first rule reachable from the UI at all, and "fine non può precedere inizio" is
    // a clearer answer than an end date that changed itself.
    if (picked != null) setState(() => _startDate = _dayOnly(picked));
  }

  Future<void> _pickEndDate() async {
    final first = _startDate;
    final last = DateUtils.addDaysToDate(first, _kSmartWorkingMaxSpanDays);
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampToWindow(_endDate, first, last),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _endDate = _dayOnly(picked));
  }

  static DateTime _clampToWindow(DateTime value, DateTime first, DateTime last) {
    final civil = _civil(value);
    if (civil.isBefore(_civil(first))) return first;
    if (civil.isAfter(_civil(last))) return last;
    return value;
  }

  /// Invalidates the list through the container rather than the (possibly disposed) widget ref.
  ///
  /// Only the "container itself is gone" case is swallowed: that means the whole app was torn down
  /// and there is no list left to refresh, whereas letting it escape would surface as an unhandled
  /// async error (`onPressed` does not await [_save]).
  static void _refreshList(ProviderContainer container) {
    try {
      container.invalidate(mySmartWorkingRequestsProvider);
    } on StateError {
      // Container already disposed — nothing left to refresh.
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    // Local, certain facts about the form first: an invalid window is refused before the round
    // trip, with the very sentence the server would have answered.
    final error = _rangeError(start: _startDate, end: _endDate, today: _openedOn);
    if (error != null) {
      showAppToast(context, message: error, tone: ToastTone.error);
      return;
    }

    // Online-only, by design: filing is a write the server must validate and decide, and an
    // "inviata" the server never saw is a lie the technician then waits on. There is no local
    // mirror and no queue for this entity (see the API client's file doc), so an offline submit is
    // refused here, visibly, and never silently queued.
    if (!ensureOnlineOrWarn(context, ref)) return;

    final reason = _reasonCtrl.text.trim();

    // Captured BEFORE the await, deliberately. If the technician backs out mid-POST this screen's
    // `ref` is disposed, and the request has still been created — the list underneath must not
    // keep showing rows that no longer describe the server's state (this entity has no local
    // mirror, so nothing else would correct it). The container outlives the route. The list
    // screen's cancel path names this as the proper fix; this is that fix.
    final container = ProviderScope.containerOf(context, listen: false);

    setState(() => _isSaving = true);

    try {
      await ref
          .read(smartWorkingRequestApiClientProvider)
          .create(
            startDate: _startDate,
            endDate: _endDate,
            reason: reason.isEmpty ? null : reason,
          );

      // Through the container, not `ref`: on the back-tap path the element is gone after the await
      // and `ref.invalidate` would throw. See [_refreshList].
      _refreshList(container);

      if (!mounted) return;
      showAppToast(
        context,
        message: 'Richiesta di smart working inviata',
        tone: ToastTone.success,
      );
      context.pop(true);
    } on SmartWorkingValidationError catch (e) {
      // The server's `detail` is the whole explanation of what to change (a date the tenant's zone
      // already calls past although the device's did not, for instance). Showing a generic
      // "riprova" instead would tell the technician to retry something only an edit can fix.
      if (mounted) showAppToast(context, message: e.detail, tone: ToastTone.error);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile inviare la richiesta. Riprova.',
          tone: ToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Visible labels the way every other date in this app is read. `DateFormat.format` formats the
    // DateTime's OWN y/m/d fields; never `.toLocal()` a civil-date label (that shows the previous
    // day west of UTC, and a smart-working marker naming a day early is the mistake this feature
    // cannot afford).
    final startLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(_startDate);
    final endLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(_endDate);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: const ScreenHeaderBar(title: 'Nuova richiesta', subtitle: 'Smart working'),
      body: ListView(
        // The form scrolls rather than overflowing when the keyboard is up (the note field grows
        // to two lines); the button sits under the fields either way.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.pagePadding,
          AppSpacing.pagePadding,
          context.navClearance,
        ),
        children: [
          AdminDateField(label: 'Data inizio', value: startLabel, onTap: _pickStartDate),
          const SizedBox(height: 16),
          AdminDateField(label: 'Data fine', value: endLabel, onTap: _pickEndDate),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Motivo (facoltativo)',
            controller: _reasonCtrl,
            maxLines: 2,
            // `SmartWorkingRequest.Reason` is varchar(1000) and the create endpoint does not
            // length-check it, so anything longer comes back as a 500 the form can only report as
            // "riprova" — a retry that can never succeed. Cap it at the source instead.
            maxLength: 1000,
            // No character counter: no other field in the app shows one, and a permanent "0/1000"
            // under an optional note is noise. The cap still applies.
            counterText: '',
          ),
          const SizedBox(height: 32),
          AppButton(
            label: 'Invia richiesta',
            onPressed: _isSaving ? null : _save,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }
}
