// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/status_stamp.dart';
import '../../../presentation/providers/schedule_providers.dart' show customerByIdProvider;
import '../../ticket/ticket_providers.dart';
import 'commesse_providers.dart';

/// Commessa detail — the wave-0 summary shell: hero + `Modifica`, then Relazioni (cantieri),
/// Sintesi (note), Attività (ticket e avanzamento), Documenti.
///
/// The commessa itself is fetched live (online-then-mirror, same as `commessaByIdProvider` uses
/// elsewhere); the linked cantieri and tickets are read from the local Drift mirror, so the two
/// relation sections work on site with no signal.
class AdminCommessaDetailScreen extends ConsumerWidget {
  const AdminCommessaDetailScreen({super.key, required this.commessaId});

  final String commessaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commessaAsync = ref.watch(commessaByIdProvider(commessaId));

    return commessaAsync.when(
      loading: () => const DetailScaffold.loading(screenTitle: 'Commessa'),
      error: (e, _) => DetailScaffold.unavailable(
        screenTitle: 'Commessa',
        icon: LucideIcons.alertTriangle,
        title: 'Commessa non disponibile',
        reason: 'Non è stato possibile leggere la commessa. Controlla la connessione e riprova.',
        onRetry: () => ref.invalidate(commessaByIdProvider(commessaId)),
      ),
      data: (commessa) {
        if (commessa == null) {
          return const DetailScaffold.unavailable(
            screenTitle: 'Commessa',
            icon: LucideIcons.briefcase,
            title: 'Commessa non trovata',
            reason: 'La commessa richiesta non è stata trovata sul server.',
          );
        }
        return _CommessaDetailBody(commessa: commessa, commessaId: commessaId);
      },
    );
  }
}

class _CommessaDetailBody extends ConsumerWidget {
  const _CommessaDetailBody({required this.commessa, required this.commessaId});

  final Map<String, dynamic> commessa;
  final String commessaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final codice = _string(commessa['codice']) ?? '—';
    final descrizione = _string(commessa['descrizione']);
    final stato = _string(commessa['stato']) ?? 'Aperta';
    final note = _string(commessa['note']);
    final customerId = _string(commessa['customerId']);
    final customerName = customerId == null
        ? null
        : ref.watch(customerByIdProvider(customerId)).valueOrNull?.companyName;
    final dataApertura = _date(commessa['dataApertura']);
    final dataChiusura = _date(commessa['dataChiusura']);
    final importoLabel = _money(commessa['importo']);

    // The prototype's hero facts: cliente · periodo · importo, in that order, each omitted when
    // the local mirror has no value for it. This is also why Sintesi never repeats them.
    final period = _period(dataApertura, dataChiusura);
    final heroFacts = [?customerName, ?period, ?importoLabel].join(' · ');

    final statoLower = stato.trim().toLowerCase();
    final statusTone = statoLower == 'aperta' || statoLower == 'in corso'
        ? DetailStatusTone.warn
        : null;

    final cantieriAsync = ref.watch(cantieriForCommessaProvider(commessaId));
    final cantieri = cantieriAsync.valueOrNull ?? const [];
    final tickets = ref.watch(ticketsForCommessaProvider(commessaId)).valueOrNull ?? const [];
    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? const <int, String>{};
    final closedStatusIds = ref.watch(closedTicketStatusIdsProvider).valueOrNull ?? const <int>{};
    final closedTickets = tickets.where((t) => ticketIsClosed(t, closedStatusIds)).length;

    final hasNote = note != null && note.trim().isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below 360 the 9px mono section meta cannot share the row with a 17px section title.
        // Drop it there; the section bodies still carry every count.
        final narrowHeader = constraints.maxWidth < 360;

        return DetailScaffold(
          screenTitle: 'Commessa',
          hero: DetailHeroData(
            variant: DetailHeroVariant.summary,
            kind: 'Summary · commessa',
            kicker: 'Summary',
            kickerContext: 'commessa',
            title: codice,
            status: DetailStatus(label: stato, tone: statusTone),
            subtitle: heroFacts.isEmpty ? null : heroFacts,
            heroCopy: descrizione == null || descrizione.trim().isEmpty ? null : Text(descrizione),
            // There is no commessa edit form or `.../modifica` route on mobile yet. Keeping the
            // prototype's primary action visible, disabled and with the reason, is honest about
            // that instead of dropping the hero's one action or shipping a dead button.
            primaryAction: const DetailAction(
              label: 'Modifica',
              enabled: false,
              disabledReason:
                  'La modifica delle commesse non è disponibile su questo telefono. Usa il '
                  'portale web.',
            ),
          ),
          sections: [
            DetailSectionData(
              title: 'Relazioni',
              trailing: narrowHeader || (cantieri.isEmpty && tickets.isEmpty)
                  ? null
                  : DetailSectionMeta(_relationMeta(cantieri.length, tickets.length)),
              isEmpty: cantieri.isEmpty,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cantieri.length; i++)
                    DetailLinkRow(
                      title: cantieri[i].name,
                      meta: _string(cantieri[i].city),
                      onTap: () => context.push('/altro/cantieri/${cantieri[i].id}'),
                      showDivider: i < cantieri.length - 1,
                    ),
                ],
              ),
            ),
            // Period and amount already sit in the hero, so Sintesi carries only the note: no fact
            // is repeated between the two, per the prototype's own rule.
            DetailSectionData(
              title: 'Sintesi',
              trailing: narrowHeader ? null : const DetailSectionMeta('Periodo, importo, note'),
              isEmpty: !hasNote,
              child: Text(
                note ?? '',
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 11.5,
                  height: 1.4,
                  color: colors.ink,
                ),
              ),
            ),
            DetailSectionData(
              title: 'Attività',
              trailing: narrowHeader ? null : const DetailSectionMeta('Ticket e avanzamento'),
              isEmpty: tickets.isEmpty,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DetailLinkRow(
                    title: 'Avanzamento',
                    meta: '$closedTickets di ${tickets.length} chiusi',
                    showDivider: true,
                  ),
                  for (var i = 0; i < tickets.length; i++)
                    DetailLinkRow(
                      title: tickets[i].numero != null
                          ? '${tickets[i].numero} · ${tickets[i].title}'
                          : tickets[i].title,
                      trailing: StatusStamp(
                        stato: statusMap[tickets[i].statusId] ?? 'Aperto',
                        size: StampSize.small,
                      ),
                      semanticsLabel:
                          '${tickets[i].numero != null ? '${tickets[i].numero}. ' : ''}${tickets[i].title}. '
                          '${statusMap[tickets[i].statusId] ?? 'Aperto'}',
                      onTap: () => context.push('/ticket/${tickets[i].id}'),
                      showDivider: i < tickets.length - 1,
                    ),
                ],
              ),
            ),
            // Documenti: the prototype lists "Contratto e allegati", but a commessa carries
            // neither a linked contract nor attachments in the API or the local mirror, so the
            // section is hidden rather than invented. Reported as a dropped fact.
          ],
        );
      },
    );
  }

  static String _relationMeta(int cantieri, int tickets) {
    final parts = [
      if (cantieri > 0) '$cantieri ${cantieri == 1 ? 'cantiere' : 'cantieri'}',
      if (tickets > 0) '$tickets ticket',
    ];
    return parts.join(' · ');
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  static String? _period(DateTime? start, DateTime? end) {
    final dm = DateFormat('dd/MM');
    if (start != null && end != null) {
      return '${dm.format(start)}–${dm.format(end)}';
    }
    if (start != null) return 'Dal ${dm.format(start)}';
    if (end != null) return 'Fino al ${dm.format(end)}';
    return null;
  }

  static String? _money(Object? value) {
    final number = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
    if (number == null) return null;
    final decimals = number == number.roundToDouble() ? 0 : 2;
    final amount = NumberFormat.decimalPatternDigits(
      locale: 'it',
      decimalDigits: decimals,
    ).format(number);
    return '€ $amount';
  }
}
