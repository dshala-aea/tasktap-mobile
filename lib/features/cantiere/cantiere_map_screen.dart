// dart format width=100
// lib/features/cantiere/cantiere_map_screen.dart
//
// The map-led cantiere view ("03 — la mappa") reachable from the detail's map card. Full-screen,
// interactive OpenStreetMap with the site pin, and the same day/primary-action card as the detail
// floating over it — so "where is it" and "am I on site" are answered on one surface.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/maps_launcher.dart';
import '../../core/widgets/widgets.dart';
import '../timbra/cantiere_timbra_screen.dart'
    show cantiereActiveSessionProvider, cantiereTodayHoursProvider, formatHoursMinutes;
import 'cantiere_close_sheet.dart';
import 'cantiere_day.dart';
import 'cantiere_providers.dart';

const String _osmUserAgentPackageName = 'com.advantedge.tasktap.tasktap_mobile';

class CantiereMapScreen extends ConsumerWidget {
  const CantiereMapScreen({super.key, required this.cantiereId});

  final String cantiereId;

  static String _statusLabel(int status) => switch (status) {
    0 => 'Attivo',
    1 => 'Completato',
    2 => 'Annullato',
    _ => '—',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantiere = ref.watch(cantiereByIdProvider(cantiereId)).valueOrNull;
    final pointAsync = ref.watch(cantiereGeocodedLocationProvider(cantiereId));
    final active = ref.watch(cantiereActiveSessionProvider);
    final activeHere = active?.cantiereId == cantiereId;
    final todayHours = ref.watch(cantiereTodayHoursProvider(cantiereId));

    final address = [
      cantiere?.address,
      cantiere?.city,
      cantiere?.postalCode,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: Stack(
        children: [
          Positioned.fill(
            child: pointAsync.when(
              loading: () =>
                  const _MapMessage(icon: LucideIcons.mapPin, message: 'Caricamento mappa…'),
              error: (e, _) => _MapMessage(
                icon: LucideIcons.mapPinOff,
                message: address.isEmpty ? 'Posizione non disponibile' : address,
              ),
              data: (point) => point == null
                  ? _MapMessage(
                      icon: LucideIcons.mapPinOff,
                      message: address.isEmpty ? 'Posizione non disponibile' : address,
                    )
                  : _CantiereMap(point: LatLng(point.lat, point.lng)),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoundIconButton(
                      icon: LucideIcons.chevronLeft,
                      semanticLabel: 'Indietro',
                      onTap: () => context.pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cantiere?.name ?? 'Cantiere',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
                            ),
                            if (address.isNotEmpty)
                              Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: context.colors.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        StatusPill(stato: _statusLabel(cantiere?.status ?? 0)),
                        const Spacer(),
                        if (activeHere)
                          CantiereLiveElapsed(
                            start: active!.startTime,
                            style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
                          )
                        else
                          Text(
                            formatHoursMinutes(todayHours),
                            style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeHere
                          ? 'Sei in cantiere dalle ${_hm(active!.startTime)}'
                          : todayHours > Duration.zero
                          ? 'Oggi su questo cantiere'
                          : 'Pronto a timbrare',
                      style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
                    ),
                    const SizedBox(height: 12),
                    if (activeHere)
                      AppButton.danger(
                        label: 'Timbra uscita',
                        icon: const Icon(LucideIcons.logOut),
                        onPressed: () => showCantiereCloseSheet(
                          context,
                          cantiereId: cantiereId,
                          cantiereName: cantiere?.name ?? 'Cantiere',
                          startTime: active!.startTime,
                        ),
                      )
                    else
                      AppButton(
                        label: 'Timbra cantiere',
                        icon: const Icon(LucideIcons.logIn),
                        onPressed: () =>
                            context.push(AppRoutes.cantiereTimbraPath(cantiereId: cantiereId)),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton.secondary(
                            label: 'Indicazioni',
                            icon: const Icon(LucideIcons.mapPin, size: 16),
                            onPressed: address.isEmpty ? null : () => openMapsForAddress(address),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppButton.ghost(
                            label: 'Dettagli',
                            icon: const Icon(LucideIcons.hardHat, size: 16),
                            onPressed: () => context.pop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _hm(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _CantiereMap extends StatefulWidget {
  const _CantiereMap({required this.point});

  final LatLng point;

  @override
  State<_CantiereMap> createState() => _CantiereMapState();
}

class _CantiereMapState extends State<_CantiereMap> {
  bool _tileLoadFailed = false;

  @override
  Widget build(BuildContext context) {
    if (_tileLoadFailed) {
      return const _MapMessage(
        icon: LucideIcons.mapPinOff,
        message: 'Mappa non disponibile senza connessione',
      );
    }

    return FlutterMap(
      options: MapOptions(initialCenter: widget.point, initialZoom: 16, minZoom: 4, maxZoom: 19),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _osmUserAgentPackageName,
          errorTileCallback: (tile, error, stackTrace) {
            if (_tileLoadFailed || !mounted) return;
            setState(() => _tileLoadFailed = true);
          },
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.point,
              width: 44,
              height: 44,
              child: const Icon(LucideIcons.mapPin, color: AppColors.Y, size: 44),
            ),
          ],
        ),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.bg2,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: context.colors.inkMuted),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.semanticLabel, required this.onTap});

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        tooltip: semanticLabel,
        icon: Icon(icon, size: 20, color: context.colors.ink),
      ),
    );
  }
}
