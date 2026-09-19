// dart format width=100
import 'package:flutter/material.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/unavailable_state.dart';

/// Landed on when `buildRouter`'s route-requirement guard (`RouteRequirement`, checked centrally
/// in the `redirect` callback) denies the destination — the module or capability it needs is not
/// held.
///
/// Deliberately NOT the same screen as `AppRoutes.altroNonDisponibile`'s placeholder
/// (`UnavailableState` paired with "not built yet on mobile" copy): that one tells a technician a
/// feature is coming and not their fault it's missing. This is a different claim — the door is
/// closed to *this account*, on purpose, and saying otherwise would be misleading about why. Both
/// reuse [UnavailableState]'s shell since the visual language (a flat sheet, a muted icon, a
/// stated reason) is right for this too — only the copy and intent differ.
class ForbiddenScreen extends StatelessWidget {
  const ForbiddenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Accesso non consentito', showBack: true),
            const Expanded(
              child: UnavailableState(
                icon: LucideIcons.xCircle,
                titolo: 'Non hai i permessi per questa sezione',
                motivo:
                    'Il tuo profilo non è abilitato a usare questa funzione. Contatta un '
                    'amministratore se pensi si tratti di un errore.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
