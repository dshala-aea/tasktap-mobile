# Native password login via a thin BFF — design

Replaces the system-browser hand-off (AppAuth, Authorization Code + PKCE
against Zitadel's hosted login page) with an in-app password form for the
common case, while keeping the existing browser flow alive as the fallback
for anything the native path doesn't (yet) handle.

## 1. Motivation

`ZitadelAuthRepository.signIn()` today opens the system browser to Zitadel's
hosted login UI for every interactive sign-in. For a field-technician app
that's otherwise fully in-app, that hand-off reads as a break in the
product — and it's the one moment where the app hands control to something
that doesn't look like TaskTap at all.

Scope for this pass: **password only**. MFA (OTP, passkey) is deliberately
deferred — the design below treats "this session needs a factor we don't
support yet" as a first-class fallback trigger rather than something to
build now, so adding real MFA later is additive, not a rework.

## 2. Why a backend-for-frontend is required, not optional

Zitadel's Session API (`CreateSession`, used to submit credentials) and the
OIDC service's `CreateCallback` (used to link a fully-authenticated session
to a pending OAuth authorization request and get back an authorization
code) both require a privileged, service-account-level credential —
confirmed against Zitadel's own API docs, which are explicit that these are
not callable by a public/native OAuth client. This isn't a design choice to
route through a backend for style; a mobile app cannot embed the credential
these two calls need without exposing it to extraction. `tasktap-api`
already holds a Zitadel service-account credential for `IIdentityAdminService`
(from the original Supabase→Zitadel migration — see the `tasktap-api` repo's
`docs/superpowers/specs/2026-07-22-stack-migration-zitadel-design.md`, §4) —
this reuses that same trust boundary rather than creating a new one.

Everything else in the flow — starting the OAuth authorization request and
exchanging the resulting code for tokens — is ordinary public-client PKCE,
identical in kind to what `ZitadelAuthRepository` already does today for
refresh, and stays entirely on the client.

## 3. Approaches considered

**A — Thin BFF, mobile keeps doing PKCE (chosen).** Mobile starts the OAuth
authorization request itself (public, unauthenticated) and does the final
token exchange itself (public client, PKCE). The backend's only job is the
two calls that structurally require a privileged credential: submit the
session, link it to the pending auth request. Smallest new backend surface;
no token-minting logic moves server-side; the existing refresh/offline-restore
code in `ZitadelAuthRepository` is untouched.

**B — Backend owns the whole exchange.** Mobile talks only to
`tasktap-api`; the backend also captures the authorization request and does
the final token exchange, returning finished tokens in one call. Simpler
mobile-side code, but the backend ends up minting user tokens and
duplicating OIDC logic the client already has, for no real security gain —
PKCE was already safe to do client-side. Rejected: more backend surface for
no benefit.

**C — Skip the BFF; polish the existing browser flow instead.** Open the
hosted login in a minimal-chrome Custom Tab / `SFSafariViewController`
instead of a full external browser, and brand Zitadel's hosted page
(logo/colors). Zero new backend work, partially addresses "feels like
leaving the app." Rejected for this pass because it doesn't get to
password-only-native or remove the round trip — but cheap enough to be the
fallback plan if A ends up deprioritized.

## 4. Data flow

1. Mobile generates its own PKCE `code_verifier`/`code_challenge` (a small
   local helper — `flutter_appauth`'s own API only knows how to drive a full
   browser round trip, so this step doesn't go through it).
2. Mobile does a plain HTTP `GET {issuer}/oauth/v2/authorize?...&code_challenge=...`
   with redirects disabled, and reads `authRequestId` off the `Location`
   header of Zitadel's 302 — the same redirect AppAuth already follows into
   a browser today, just intercepted before anything renders.
3. Mobile `POST`s `{authRequestId, username, password}` to a new
   `tasktap-api` endpoint, `POST /api/auth/login`.
4. The backend, using the existing service-account credential, calls
   Zitadel's `CreateSession` (user + password checks) and, if the session is
   fully authenticated, `CreateCallback` to link it to the pending
   `authRequestId`. Returns `{ code }` on success, or a typed failure
   (`invalid_credentials` | `additional_factor_required` | upstream error).
5. On success, mobile exchanges `code` + its own `code_verifier` at Zitadel's
   token endpoint via `flutter_appauth`'s `TokenRequest` (`grantType:
   authorization_code`) — the same request shape `refreshSession()` already
   issues for the refresh grant. The result flows through the existing
   `_fromTokens` → persist → emit path unchanged.

## 5. Components

- **Backend:** one new endpoint, `POST /api/auth/login`
  (`{authRequestId, username, password} → { code }` or a typed failure),
  implemented alongside the existing Zitadel service-account client used by
  `IIdentityAdminService`. No new credential, no new deployable.
- **Mobile:** `IAuthRepository` gains one additive method,
  `signInWithPassword(username, password)`. `signIn()` (the existing browser
  flow) is untouched and becomes the fallback target, not a deprecated path.
- **Mobile UI:** a new native login screen (username/password fields,
  submit, "Password dimenticata?" link) replaces the current single
  "Accedi" button screen.

## 6. Error handling

One fallback mechanism (call the existing `signIn()`), three triggers, plus
two failure modes that do not fall back:

| Trigger | Behavior |
|---|---|
| Wrong password | Inline error on the native form, retry in place. No fallback. |
| Backend reports a factor beyond password is required (future MFA) | Brief transition message, then automatically call `signIn()` (browser). No dead end. |
| User taps "Password dimenticata?" | Same fallback to `signIn()` — Zitadel's own hosted page already has its own reset link; no need to deep-link further. |
| Network error (at the authorize-redirect step, the backend call, or the token exchange) | Normal retry messaging on the native form. No fallback — the browser flow needs the same network. |
| Unexpected backend/Zitadel error (5xx, malformed response) | Error message with a manual "Accedi con il browser" button. Not automatic — an unexpected error may just repeat in the browser flow too. |

## 7. Testing

- **Backend:** unit tests on `POST /api/auth/login` against a mocked Zitadel
  HTTP client — success, wrong password, additional-factor-required,
  Zitadel unreachable/5xx.
- **Mobile:** unit tests on `signInWithPassword` against a mocked Dio client
  covering the same four outcomes (success, invalid credentials,
  factor-required triggers fallback, network error triggers no fallback).
  Widget test on the new login screen — form validation, error display,
  loading state, "Password dimenticata?" behavior.
- No live-Zitadel end-to-end test, matching the existing pattern in
  `test/data/auth/zitadel_auth_repository_test.dart`, which mocks
  `FlutterAppAuth` rather than hitting a real IdP.

## 8. Non-goals

- MFA/OTP/passkey — deferred; the additional-factor-required fallback is the
  seam this attaches to later, not something built now.
- Social/SSO login — out of scope, not currently used by this app.
- Removing or deprecating the browser-based `signIn()` — it remains the
  fallback path permanently (forgot-password, future MFA, unexpected
  errors), not a transitional shim to delete later.
- Any change to token storage, refresh behavior, or offline-restore — all of
  that is downstream of `_fromTokens` and is reused unchanged.
