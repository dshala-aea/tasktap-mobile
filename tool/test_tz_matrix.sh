#!/usr/bin/env bash
# Runs the business-time test subset under several device zones, as the CI `tz-matrix` job does.
# Stops at the first failure. Usage: bash tool/test_tz_matrix.sh
set -euo pipefail
cd "$(dirname "$0")/.."

for tz in Europe/Rome UTC America/Los_Angeles Pacific/Auckland; do
  echo "=== TZ=$tz ==="
  TZ="$tz" flutter test --no-pub \
    test/core/time \
    test/data/timbratura \
    test/data/worklog_date_parsing_test.dart \
    test/data/worklog_wire_shape_test.dart \
    test/features/timbra \
    test/features/rapportino/steps \
    test/features/ticket/worklog_row_date_test.dart \
    test/features/ticket/ticket_timer_elapsed_test.dart \
    test/features/ticket/ticket_detail_screen_test.dart \
    test/features/altro/notifiche_screen_test.dart
done
echo "tz matrix: all zones green"
