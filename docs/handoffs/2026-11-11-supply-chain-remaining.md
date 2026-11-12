# Handoff — supply chain, remaining items

**To:** backend, frontend, ops
**From:** mobile
**Date:** 2026-11-11
**ClickUp:** [P1][SEC] Supply chain (`12493t4qzth`)

## Shipped on mobile

- **Dependabot** (`.github/dependabot.yml`) for the `pub` and `github-actions` ecosystems, weekly,
  grouped, with a 5-PR cap.
- **OSV-Scanner** (`.github/workflows/security.yml`) on push/PR and weekly, scanning
  `pubspec.lock`; results go to Security › Code scanning.
- **CycloneDX SBOM** generated on every run and uploaded as the `tasktap-mobile-sbom` artifact.
- GitHub Actions remain pinned by commit SHA; Dependabot updates them deliberately.

## Remaining

1. **Backend / frontend:** add equivalent Dependabot/Renovate, OSV or CodeQL scanning, and SBOM
   generation for those repos. Nothing in this mobile change covers them.
2. **Ops:** replace the unofficial MinIO image with the supported one; fix the SonarQube token or
   switch to CodeQL; add image scanning (Trivy/Grype) for the deployed containers.
3. **Repo settings:** confirm Dependabot alerts/security updates and secret scanning + push
   protection are enabled on all repos (secret scanning is a separate ClickUp item).
4. **Dependency review:** optionally add `actions/dependency-review-action` to PRs for a
   vulnerability/licence gate; OSV already reports, but dependency-review can block a new vulnerable
   package before merge.
