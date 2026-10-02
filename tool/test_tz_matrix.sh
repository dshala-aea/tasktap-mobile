#!/usr/bin/env bash
# Runs the business-time test subset under several device zones, as the CI `tz-matrix` job does.
# Stops at the first failure. Usage: bash tool/test_tz_matrix.sh
set -euo pipefail
cd "$(dirname "$0")/.."

for tz in Europe/Rome UTC America/Los_Angeles Pacific/Auckland; do
  echo "=== TZ=$tz ==="
  TZ="$tz" flutter test --no-pub test/core/time test/data/timbratura test/features/timbra test/features/rapportino/steps
done
echo "tz matrix: all zones green"
