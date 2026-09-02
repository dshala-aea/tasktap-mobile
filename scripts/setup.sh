#!/usr/bin/env bash
# One-time dev setup: install deps, generate code, and wire up the git hooks
# that keep generated code (drift, riverpod) in sync automatically on future
# pulls/branch switches — see .githooks/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
dart run build_runner build --delete-conflicting-outputs
git config core.hooksPath .githooks

echo
echo "Setup complete."
echo "  - Generated code (drift, riverpod) is up to date."
echo "  - .githooks is now active: future 'git pull'/'git checkout' will"
echo "    auto-regenerate it, so you shouldn't need to run build_runner by hand"
echo "    except during active schema/provider editing (see README: 'dart run"
echo "    build_runner watch')."
