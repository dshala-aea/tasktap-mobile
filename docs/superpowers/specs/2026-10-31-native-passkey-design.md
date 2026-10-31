# Native passkey sign-in — design

Status: proposed. Supersedes the passkey half of
`2026-08-27-native-login-bff-design.md` (§8 deferred MFA/passkey); the
password flow described there is unchanged.

## 1. Intent

Let a technician sign in with a passkey (Face ID / Touch ID / fingerprint /
screen lock) instead of typing a password, without leaving the app. Password
stays the default method; the passkey button is opt-in and only appears where
the device can honour it. Users arrive by invitation, so enrolment happens
after the first password login, not during activation.

Why native rather than the existing browser fallback: the browser hand-off is
the one moment the app stops looking like TaskTap, and passkeys are precisely
the flow where users expect a single biometric prompt inside the app.

## 2. What exists today

- Password login already runs natively through a thin BFF: mobile captures the
  OIDC `authRequest` id, `POST /api/MobileAuth/login` drives ZITADEL's Session
  API (`CreateSession` → `SetSession` with the password check → `CreateCallback`),
  and mobile exchanges the returned code with PKCE (`ZitadelAuthRepository`,
  `ZitadelSessionService`, `MobileAuthController`).
- When the account needs more than a password, the backend answers
  `additional_factor_required` and the app falls back to the system-browser
  OIDC flow (`LoginNotifier.signInWithPassword` → `signIn`).
- Two open PRs attempt passkeys (tasktap-api#191, tasktap-mobile#171). They are
  directionally right and unusable as written; §12 lists the defects. This
  design supersedes them pending the work below.

## 3. Constraints that shape the design

1. **Passkeys are bound to the issuer domain.** RP ID is `auth.tasktap.it`;
   an assertion for any other RP ID will not match credentials created against
   ZITADEL.
2. **ZITADEL must publish the OS association files.** Since v4.17.0 ZITADEL
   serves `/.well-known/assetlinks.json` and
   `/.well-known/apple-app-site-association` from the *Native App Links*
   settings of an OIDC **Native** application. The deployed instance pins
   `v4.16.1` and both endpoints currently return `404 {"code":5,"message":"Not Found"}`,
   so **an upgrade to ≥ v4.17 is a hard prerequisite**.
3. **The login policy must allow passwordless (passkeys).** If the org policy
   requires password + MFA instead, a passkey-only session cannot be finalised
   and `CreateCallback` answers 412 → `additional_factor_required`.
4. **The mobile app must be associated with the domain**: `webcredentials:auth.tasktap.it`
   in the iOS entitlements; Android relies on the served Digital Asset Links
   plus the app's signing fingerprints.
5. Only the BFF may hold ZITADEL credentials: `IAM_LOGIN_CLIENT` (session
   finalisation) and the Management service account (user/passkey admin).
   Neither may ship in the app.
6. Same offline-first invariants as the password flow: tokens in memory,
   refresh token in secure storage, identity snapshot cached, no sign-out on
   network failure.

## 4. Approaches considered

**A — Native BFF passkey (chosen).** Mobile performs the WebAuthn assertion
with the platform authenticator; the BFF makes the two privileged ZITADEL
calls and returns the authorization code; mobile exchanges it with PKCE.
Enrolment is also BFF-mediated. Fully native, symmetric with the password
flow, and the shape ZITADEL documents for custom login UIs.

**B — Passkey as a second factor** (password check, then WebAuthN check in the
same session). Only needed if the policy forces MFA. Rejected as the initial
model: it makes passkey an add-on rather than an alternative sign-in, and the
user asked for an opt-in alternative.

**C — Hosted login in a Custom Tab / `ASWebAuthenticationSession`.** Works
today, no upgrade or entitlements, but leaves the app UI. Kept only as the
existing fallback when a session needs more factors than the native path can
supply; not the delivery mechanism.

## 5. Responsibilities

- **ZITADEL**: credential storage and assertion verification, session
  finalisation, association-file publication, policy.
- **API (BFF)**: privileged session calls (login), privileged user-service
  calls (enrolment/list/delete), RP ID resolution, passkey-existence check,
  error contract, audit.
- **Mobile**: platform authenticator invocation, PKCE token exchange, session
  storage/refresh (unchanged), availability gating, UI, error mapping.

The API never sees key material — only a signed challenge response.

## 6. Configuration

### ZITADEL (ops)

1. Upgrade `zitadel` and `zitadel-login` images together to ≥ v4.17
   (recommend the same v4.20.x minor). Back up the database; the upgrade runs
   forward-only migrations, so rollback means restore, not re-pinning.
2. OIDC application type must be **Native**. In *Native App Links* set:
   - iOS: Team ID (10 alphanumerics) and Bundle ID
     `com.advantedge.tasktap.tasktapMobile`;
   - Android: package `com.advantedge.tasktap.tasktap_mobile`, SHA-256 of the
     release **and** debug signing certificates.
3. Login policy: allow passwordless (passkeys) for the organisation.
4. Verify: `curl -i https://auth.tasktap.it/.well-known/assetlinks.json` and
   `.../apple-app-site-association` → 200, `application/json`,
   `Cache-Control: no-store`, contents match the app.

### API

New setting `ZitadelOptions.WebAuthnRpId`, defaulting to the host of
`ZitadelOptions.Url`. **The RP ID is never read from a request.**

### Mobile

- iOS: add `com.apple.developer.associated-domains` =
  `webcredentials:auth.tasktap.it` to `Runner.entitlements`; enable the
  Associated Domains capability for the bundle id in the Apple Developer
  portal so CI's provisioning profile includes it.
- Android: confirm `minSdk ≥ 23` (the `passkeys_android` floor). No manifest
  change is required for Credential Manager.
- Both: the builds under test must be signed with the fingerprints registered
  in ZITADEL — debug, the local release/upload key, **and the Play app-signing
  certificate** (Google Play re-signs uploaded builds, so without Play's
  fingerprint passkeys work on locally installed release APKs and fail on
  Play-installed ones).
- Environments: the RP ID is derived from `OIDC_ISSUER`, so a staging issuer
  works without code changes, but each issuer host also needs its own
  association files and an iOS entitlement entry
  (`webcredentials:<staging-host>`). Production is the only confirmed target;
  see §18.

## 7. Sign-in flow

1. User types their email and taps **Accedi con passkey** (shown only when the
   platform supports passkeys).
2. Mobile generates PKCE and captures the `authRequest` id exactly as the
   password flow does.
3. `POST /api/MobileAuth/passkey/login/start {authRequestId, loginName}`.
   Server: resolve user by email → `GET /v2/users/{id}/passkeys` (admin
   credential) → if empty, `no_passkey_registered`; else
   `POST /v2/sessions` with `checks.user` and
   `challenges.webAuthN {domain: rpId, userVerificationRequirement: REQUIRED}`.
   Returns `{sessionId, sessionToken, publicKeyCredentialRequestOptions}`.
4. Mobile unwraps `publicKey`, builds `AuthenticateRequestType.fromJson`, runs
   `PasskeyAuthenticator.authenticate`, and serialises the result with
   `toJson()` (the nested `{id, rawId, type, response{...}}` shape).
5. `POST /api/MobileAuth/passkey/login/complete
   {authRequestId, sessionId, sessionToken, credentialAssertionData}` (the login
   identity is the session's, never a request field).
   Server: `PATCH /v2/sessions/{id}` with `checks.webAuthN`, then
   `CreateCallback` → `{code}`.
6. Mobile exchanges the code with PKCE (`flutter_appauth`), persists the
   refresh token and cached identity, emits the user. Unchanged from the
   password path.

Session token handling: it is returned to the client because the Session API
requires it on the follow-up call; it is short-lived and bound to one session.
Never persisted.

## 8. Enrolment flow

Prerequisite: the user is signed in (password or passkey) and the bearer token
identifies them (`sub`).

1. Settings → Sicurezza → **Attiva accesso con passkey**.
2. `POST /api/MobileAuth/passkey/register/start` (authenticated, no body).
   Server resolves the user from `sub` (never from the payload) →
   `POST /v2/users/{id}/passkeys {authenticator: PASSKEY_AUTHENTICATOR_UNSPECIFIED}`
   → `{passkeyId, publicKeyCredentialCreationOptions}`.
3. Mobile unwraps `publicKey`, builds `RegisterRequestType.fromJson`, runs
   `PasskeyAuthenticator.register` (biometric prompt), serialises with
   `toJson()`.
4. `POST /api/MobileAuth/passkey/register/complete
   {passkeyId, publicKeyCredential, passkeyName}` →
   `POST /v2/users/{id}/passkeys/{passkeyId}` → 204.

`MobileAuthController` is `[AllowAnonymous]` at class level and `[Authorize]`
on an action does not override that, so the class attribute must be removed and
`[AllowAnonymous]` applied to the sign-in actions instead. Password login must
stay anonymous; an explicit test guards it.
5. Settings shows the registered passkey (from `GET /api/MobileAuth/passkey`),
   with a remove action (`DELETE /api/MobileAuth/passkey/{id}`). The action is
   labelled "Rimuovi passkey" and deletes the credential only: it does **not**
   revoke a refresh token already held on that device. Ending sessions stays
   with the existing logout/forced-sign-out paths. ZITADEL's self-service
   remains available.

The enrolment screen carries an explicit warning that a passkey is unlocked by
this device's screen lock and should only be enrolled on a personal device.
Passkey sign-in itself is offered on every supported device: enrolment is the
user's opt-in choice, and a tenant-level switch is out of scope for this pass
(shared/rotating tablets are addressed by the warning, not by a gate).

No local enrolment hint is stored. The login button's visibility depends only
on platform support, and the server's `no_passkey_registered` answer is
authoritative. A stored hint would either die on sign-out (making it useless
exactly when the login screen needs it) or survive sign-out and leak the
previous user's state on a shared device — both are worse than the button
simply being present.

## 9. API contract

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| POST | `/api/MobileAuth/passkey/login/start` | anonymous | `{authRequestId, loginName}` | `{sessionId, sessionToken, publicKeyCredentialRequestOptions}` |
| POST | `/api/MobileAuth/passkey/login/complete` | anonymous | `{authRequestId, sessionId, sessionToken, credentialAssertionData}` | `{code}` |
| POST | `/api/MobileAuth/passkey/register/start` | bearer | `{}` | `{passkeyId, publicKeyCredentialCreationOptions}` |
| POST | `/api/MobileAuth/passkey/register/complete` | bearer | `{passkeyId, publicKeyCredential, passkeyName}` | 204 |
| GET | `/api/MobileAuth/passkey` | bearer | — | `[{id, name}]` |
| DELETE | `/api/MobileAuth/passkey/{id}` | bearer | — | 204 |

Exactly one of `loginName`/user is derived server-side per endpoint; no
endpoint accepts an RP ID or a user id from the caller.

Error codes (400 unless noted): `no_passkey_registered`,
`passkey_verification_failed`, `additional_factor_required`,
`passkey_registration_failed` (enrolment 4xx other than 401/403),
`identity_provider_unavailable` (503). All are logged without credential
material.

Mobile copy for `passkey_registration_failed`: "Impossibile attivare la
passkey. Riprova."


`no_passkey_registered` is returned **both** for an unknown email and for a
known user with no enrolled passkey, so `login/start` does not become an
account-existence oracle. The distinction survives only in server logs.
Password login keeps its own `invalid_credentials` contract, unchanged.

## 10. Mobile contract

Provider graph note: `dioProvider` already reads `authRepositoryProvider`
through `sessionEnderProvider`, so the auth repository cannot depend on the
authenticated Dio without a cycle. Enrolment therefore lives in its own client
that reads `dioProvider`, not on `IAuthRepository`.

- `PasskeySupport` (`lib/core/security/passkey_support.dart`) —
  `Future<bool> isAvailable()`, wrapping
  `PasskeyAuthenticator().getAvailability()`: Android requires
  `hasPasskeySupport && isUserVerifyingPlatformAuthenticatorAvailable`, iOS
  requires `hasPasskeySupport && hasBiometrics`. Exposed as
  `passkeySupportedProvider`.
- `IAuthRepository.signInWithPasskey(String loginName)` — same result shape as
  `signInWithPassword`. Implemented on the repository because sign-in needs no
  authenticated Dio.
- `PasskeyEnroller` (`lib/data/auth/passkey_enroller.dart`) —
  `Future<({bool ok, AuthFailure? failure})> enrol({required String name})`,
  using the Dio from `dioProvider`; consumed by the settings screen through
  `passkeyEnrollerProvider`.

New `AuthFailure` cases with Italian copy:

- `PasskeyNotRegistered` — "Nessuna passkey disponibile. Accedi con la
  password; potrai attivarla dalle impostazioni dopo l'accesso." The same case
  covers "account has no passkey" and "this device has no credential for the
  account", so the copy must not claim which.
- `PasskeyUnavailable` — device/OS cannot use passkeys.
- `PasskeyCancelled` — user dismissed the sheet; shown as a no-op, never as an
  error banner.

`PasskeyAuthCancelledException` → `PasskeyCancelled`;
`NoCredentialsAvailableException` → `PasskeyNotRegistered`;
`DomainNotAssociatedException` / `PasskeyUnsupportedException` →
`PasskeyUnavailable` (plus a diagnostic log line, since this means the
association files or signing fingerprints are wrong).

UI: a secondary "Accedi con passkey" button on the login screen behind the
availability gate; a Sicurezza section in Impostazioni for enrolment and
revocation. Password remains the primary, always-visible action.

## 11. Error handling

| Situation | Behaviour |
|---|---|
| Unknown email on the passkey path | `PasskeyNotRegistered` (same as "no passkey"; no oracle) |
| User or device has no passkey | `PasskeyNotRegistered`, hint to use password and enrol after sign-in |
| Wrong password (password form) | `invalid_credentials`, inline retry |
| Assertion rejected | `passkey_verification_failed`, retry once, then password |
| User cancels the sheet | no-op |
| Device cannot do passkeys | button hidden; enrolment entry disabled with reason |
| RP ID not associated (config broken) | `PasskeyUnavailable`, generic message, log with detail |
| Policy needs more factors (callback 412) | `additional_factor_required` → existing browser fallback |
| ZITADEL down / 401 on the service credential | 503 `identity_provider_unavailable`, never "wrong password" |
| Network failure | retry message; no session teardown |

## 12. Defects to fix in the open PRs

1. `jsonDecode(jsonEncode(assertion))` throws — use the package's `toJson()`.
2. ZITADEL returns the options wrapped in `publicKey`; both
   `AuthenticateRequestType.fromJson` and `RegisterRequestType.fromJson` expect
   the unwrapped object.
3. `rpId` is accepted from the request body; derive it server-side.
4. No enrolment, so no credential can exist.
5. No availability gate and no cancellation/`no credentials` mapping.
6. `additional_factor_required` is not handled on the passkey path.
7. Association-file premise in PR #171's body is wrong: ZITADEL serves them;
   the ops work is the upgrade plus the app's Native App Links settings.

## 13. Security

- No key material or ZITADEL service credential ever reaches the device.
- Enrolment endpoints bind to the caller's `sub`; a caller cannot enrol for
  another user. Register/complete ignores any client-supplied user id.
- `login/start` must not confirm whether an account exists: unknown email and
  "known user without passkeys" return the identical `no_passkey_registered`.
- Rate limiting stays on the controller; per-email throttling of
  `login/start` is a follow-up.
- Audit: `auth.login.passkey` (with user/tenant when resolvable) and
  `auth.passkey.register` / `auth.passkey.delete`.
- Assertion payloads are logged only as success/failure, never body.

## 14. Testing

API (unit, scripted HTTP handler as in `ZitadelSessionServiceTests`):
- start: happy path, no passkeys, unknown email, missing
  `publicKeyCredentialRequestOptions`, upstream 5xx/401.
- complete: accepted assertion, rejected assertion, callback 412, missing
  session token.
- enrolment: start/complete, caller/`sub` mismatch refused, SA used, upstream
  faults.
- endpoint tests for the error contract and 401 on unauthenticated enrolment.

Mobile (unit/widget):
- start returns `no_passkey_registered` identically for unknown email and a
  user without passkeys (no oracle);
- assertion serialisation uses `toJson()`;
- `publicKey` unwrapping for both flows;
- error mapping for every `AuthFailure` case, cancellation is a no-op;
- availability gate hides the button;
- login screen and settings tests.

Manual device matrix (required before release):
- Android emulator with Play Store + screen lock, and a physical device;
- iPhone with Face ID (simulator with enrolled biometrics + a physical device);
- register → sign out → sign in with passkey → remove in settings → sign-in
  shows `PasskeyNotRegistered`;
- debug, local release and Play-installed builds all have their signing
  fingerprints in `assetlinks.json`, and the Play-installed build is exercised
  at least once.

## 15. Rollout

1. ZITADEL upgrade + association endpoints verified (ops).
2. Native App Links configured; JSON contents verified (ops).
3. Apple capability enabled; iOS build with the entitlement produced (mobile
   release config).
4. API deployed (endpoints inert until the app ships).
5. Mobile release; the passkey button only appears on supported devices.
6. Fallback intact: password and browser flows untouched.

## 16. Non-goals

- Passkey as a second factor after the password (approach B).
- Conditional UI / autofill integration.
- Cross-device (QR) passkey flows.
- Removing password login.
- Web or kiosk passkeys.
- Passkey-based re-authentication for the app lock (`BiometricLock` keeps using
  `local_auth`).
- A tenant/admin switch that disables passkeys on shared devices.

## 17. Anti-goals

- A passkey button that can only fail because no credential exists.
- Silently downgrading a failed passkey attempt to the password form.
- Shipping on an instance that does not serve the association files.
- Storing anything passkey-related in app storage.

## 18. Inputs still needed

Decisions taken (asked and confirmed during review):

1. **Shared devices.** Passkeys are offered everywhere; enrolment (not
   sign-in) is the gate, and the enrolment screen warns that a passkey is tied
   to the device's screen lock and belongs on a personal device. A tenant-level
   switch is deferred.
2. **Revocation semantics.** Removing a passkey deletes the credential only.
   It does not end the device's existing session; logout and forced sign-out
   keep their current behaviour. Copy says "Rimuovi passkey".
3. **Environments.** Production only for the first release. A staging issuer
   can be added later with an additional entitlement entry and its own
   association configuration; the code already derives the RP ID from
   `OIDC_ISSUER`.

Operational values (needed before the ZITADEL/Apple configuration, not before
planning):

- Apple Team ID; debug, local-release and Play app-signing SHA-256
  fingerprints.
- Confirmation of the deployed ZITADEL version (the endpoints' 404 suggests
  < 4.17).
- Confirmation that the login policy allows passwordless (otherwise passkey
  sign-in falls back to `additional_factor_required`).
- Confirmation that the Management service account may manage passkeys for
  users. Verify `POST /v2/users/{id}/passkeys` in staging. If it cannot, the
  fallback stays native: `POST /v2/users/{id}/passkeys/registration_link`
  with `returnCode` yields a code the app submits on the same start call —
  no browser hand-off — or a dedicated least-privilege role is provisioned.
