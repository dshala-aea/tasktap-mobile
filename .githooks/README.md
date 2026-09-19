# .githooks

Hooks that keep generated code (`*.g.dart` — drift tables, riverpod providers)
in sync automatically, so it's never manually-generated-and-forgotten.

Not active by default — plain `git clone` doesn't wire these up. Run
`scripts/setup.sh` once per clone; it sets `core.hooksPath` to this directory.

- `post-merge` — runs after `git pull`/`git merge` brings in new commits.
- `post-checkout` — runs after switching branches (not after a single-file
  `git checkout -- file`).

Both just run `dart run build_runner build --delete-conflicting-outputs`.
build_runner is incremental, so this is fast except right after a big schema
change. During active schema/provider editing, run
`dart run build_runner watch --delete-conflicting-outputs` instead of relying
on these hooks — it regenerates on every save.
