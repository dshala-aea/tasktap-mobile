# Native Passkey Sign-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a technician sign in with a platform passkey, and enrol or remove one after signing in, without leaving the app.

**Architecture:** Mobile runs the WebAuthn ceremony with the platform authenticator; the .NET BFF makes the privileged ZITADEL Session API calls for sign-in and the User Service calls for enrolment, so no service credential or key material reaches the device. The RP ID is always derived server-side from the ZITADEL issuer. Password remains the default method.

**Tech Stack:** Flutter (`passkeys` 2.23.x, `flutter_appauth`), .NET 10 minimal API/controllers, ZITADEL ≥ v4.17.

**Spec:** `docs/superpowers/specs/2026-10-31-native-passkey-design.md` (mobile repo)

**Repositories:** API tasks run in `~/tt-worktrees/api-passkey` (branch `feat/passkey-signin`, PR dshala-aea/tasktap-api#192). Mobile tasks run in `~/tt-worktrees/mobile-passkey` (branch `feat/passkey-login`, PR dshala-aea/tasktap-mobile#171). Commit in the repository each task belongs to.

## Global Constraints

- ZITADEL must be ≥ v4.17.0; the deployed default is v4.16.1 and both association endpoints return 404 today.
- RP ID = host of `ZitadelOptions.Url` (`auth.tasktap.it`). Never read an RP ID from a request.
- Error codes are exactly: `no_passkey_registered`, `passkey_verification_failed`, `additional_factor_required`, `identity_provider_unavailable`, plus the existing `invalid_credentials` for the password path.
- `no_passkey_registered` is returned identically for an unknown email and a known user without passkeys.
- No passkey material, session token, or ZITADEL credential is persisted on the device.
- Password login and the browser fallback are unchanged.
- Italian copy is fixed by the spec; do not paraphrase it in UI or tests.
- Passkey features are shown only when `PasskeySupport.isAvailable()` is true.

## Review Focus

1. **Cancelling the biometric sheet** must clear the spinner and show no error banner; anything else reads as a failure of the login form.
2. **No credential on this device** (shared tablet, restored phone) must produce the neutral "nessuna passkey" hint, never a crash and never a sign-out.
3. **Malformed options** (ZITADEL wrapping changed, `publicKey` missing) must surface as a generic auth error, not a runtime exception.
4. **RP ID / association misconfigured** must fail once with a generic message and a server log line, never loop the sheet.
5. **Enrolment interrupted after the biometric prompt** (network loss, `register/complete` 503) must not leave the UI claiming the passkey exists.
6. **Double-tapping the passkey button** must not start two ceremonies or two token exchanges.

---

### Task 1: ZITADEL readiness (API repo, ops + version pin)

**Files:**
- Modify: `docker-compose.coolify.yml` (`ZITADEL_VERSION` default)
- Modify: `.env.coolify.example` if it documents the pin

**Interfaces:**
- Produces: an instance that serves `/.well-known/assetlinks.json` and `/.well-known/apple-app-site-association` with the app's entries.

- [ ] **Step 1: Confirm the target tags exist**

```bash
docker manifest inspect ghcr.io/zitadel/zitadel:v4.20.0 >/dev/null && echo api-ok
docker manifest inspect ghcr.io/zitadel/zitadel-login:v4.20.0 >/dev/null && echo login-ok
```

Expected: `api-ok` and `login-ok`. If the login image has no `v4.20.0`, use the newest tag that exists for both; record it.

- [ ] **Step 2: Bump the default in `docker-compose.coolify.yml`**

Change `${ZITADEL_VERSION:-v4.16.1}` to `${ZITADEL_VERSION:-v4.20.0}` on both the `zitadel` and `zitadel-login` images (they must stay in lockstep — the existing comment says so).

- [ ] **Step 3: Commit**

```bash
git add docker-compose.coolify.yml .env.coolify.example
git commit -m "chore(deploy): raise the ZITADEL pin for native passkey association files"
```

- [ ] **Step 4: Deploy with a database backup first** (manual, outside CI)

Take a Postgres dump of the ZITADEL database, then redeploy. ZITADEL runs forward-only migrations; rollback means restoring the dump.

- [ ] **Step 5: Configure Native App Links** (ZITADEL Console → project → the mobile OIDC **Native** application → Native App Links)

- iOS Team ID: the Apple team id (10 alphanumerics).
- iOS Bundle ID: `com.advantedge.tasktap.tasktapMobile`.
- Android package: `com.advantedge.tasktap.tasktap_mobile`.
- Android SHA-256: debug, local release, and the **Play app-signing** certificate.
- Login policy: allow passwordless (passkeys) for the organisation.

- [ ] **Step 6: Verify the served documents**

```bash
curl -si https://auth.tasktap.it/.well-known/assetlinks.json | head -20
curl -si https://auth.tasktap.it/.well-known/apple-app-site-association | head -20
```

Expected: `HTTP/2 200`, `content-type: application/json`, `cache-control: no-store`, and JSON containing `com.advantedge.tasktap.tasktap_mobile` plus the fingerprints, and `{team}.com.advantedge.tasktap.tasktapMobile`.

---

### Task 2: WebAuthn RP ID setting (API repo)

**Files:**
- Modify: `src/TaskTapAPI.Application/Services/Identity/ZitadelOptions.cs`
- Test: `tests/TaskTapAPI.Tests/Services/ZitadelOptionsTests.cs` (create)

**Interfaces:**
- Produces: `string ZitadelOptions.WebAuthnRpId { get; set; }` and `string ZitadelOptions.EffectiveWebAuthnRpId { get; }`.

- [ ] **Step 1: Write the failing tests**

```csharp
[Fact]
public void EffectiveWebAuthnRpId_defaults_to_the_issuer_host()
{
    var options = new ZitadelOptions { Url = "https://auth.tasktap.it" };
    options.EffectiveWebAuthnRpId.Should().Be("auth.tasktap.it");
}

[Fact]
public void EffectiveWebAuthnRpId_honours_an_explicit_value()
{
    var options = new ZitadelOptions { Url = "https://auth.tasktap.it", WebAuthnRpId = "login.example.test" };
    options.EffectiveWebAuthnRpId.Should().Be("login.example.test");
}

[Fact]
public void EffectiveWebAuthnRpId_is_empty_when_no_issuer_is_configured()
{
    new ZitadelOptions().EffectiveWebAuthnRpId.Should().BeEmpty();
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `dotnet test tests/TaskTapAPI.Tests/TaskTapAPI.Tests.csproj --filter "FullyQualifiedName~ZitadelOptionsTests"`
Expected: compile failure (`EffectiveWebAuthnRpId` not defined).

- [ ] **Step 3: Implement the property**

`EffectiveWebAuthnRpId` returns `WebAuthnRpId` when non-blank, else `new Uri(Url).Host` when `Url` parses as an absolute URI, else `string.Empty`.

- [ ] **Step 4: Re-run**

Run: same command. Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add src/TaskTapAPI.Application/Services/Identity/ZitadelOptions.cs tests/TaskTapAPI.Tests/Services/ZitadelOptionsTests.cs
git commit -m "feat(identity): make the WebAuthn RP ID server configuration"
```

---

### Task 3: Passkey administration service (API repo)

**Files:**
- Create: `src/TaskTapAPI.Application/Services/Identity/IZitadelPasskeyAdminService.cs`
- Create: `src/TaskTapAPI.Application/Services/Identity/ZitadelPasskeyAdminService.cs`
- Modify: `src/TaskTapAPI.Api/Program.cs` (typed HttpClient registration, beside the other `IZitadel*` registrations at ~line 285)
- Test: `tests/TaskTapAPI.Tests/Services/ZitadelPasskeyAdminServiceTests.cs` (create)

**Interfaces:**
- Consumes: `IZitadelTokenProvider.GetAccessTokenAsync`, `ZitadelOptions.ApiBaseUrl`.
- Produces:
  - `record PasskeyInfo(string Id, string Name)`
  - `record PasskeyRegistrationChallenge(string PasskeyId, JsonElement PublicKeyCredentialCreationOptions)`
  - `Task<IReadOnlyList<PasskeyInfo>> ListAsync(string userId, CancellationToken ct)`
  - `Task<PasskeyRegistrationChallenge> StartRegistrationAsync(string userId, CancellationToken ct)`
  - `Task CompleteRegistrationAsync(string userId, string passkeyId, JsonElement publicKeyCredential, string name, CancellationToken ct)`
  - `Task RemoveAsync(string userId, string passkeyId, CancellationToken ct)`

Base address `{ApiBaseUrl}/v2/`, bearer from the admin token provider, paths `users/{id}/passkeys`.

- [ ] **Step 1: Write the failing tests**

Use the `ScriptedHandler`/`RecordedRequest` pattern from `tests/TaskTapAPI.Tests/Services/ZitadelSessionServiceTests.cs` and a fake `IZitadelTokenProvider` returning `"admin-token"`.

Tests (names and assertions):

```csharp
ListAsync_ReturnsThePasskeysFromTheUserService            // GET .../v2/users/u1/passkeys; id+name parsed
ListAsync_MapsUpstream401ToServiceUnavailable             // throws ServiceUnavailableException, code identity_provider_unavailable
StartRegistrationAsync_SendsTheAuthenticatorAndReturnsTheChallenge // POST .../v2/users/u1/passkeys, body authenticator == PASSKEY_AUTHENTICATOR_UNSPECIFIED; returns passkeyId + options
StartRegistrationAsync_MissingOptionsIsServiceUnavailable // 200 with no publicKeyCredentialCreationOptions
CompleteRegistrationAsync_PostsTheCredentialAndName       // POST .../passkeys/pk1, body publicKeyCredential + passkeyName
RemoveAsync_DeletesThePasskey                             // DELETE .../passkeys/pk1
RemoveAsync_NotFoundIsIdempotent                          // 404 does not throw
AllCalls_CarryTheAdminBearerToken                         // Authorization: Bearer admin-token
```

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/TaskTapAPI.Tests/TaskTapAPI.Tests.csproj --filter "FullyQualifiedName~ZitadelPasskeyAdminServiceTests"`
Expected: compile failure.

- [ ] **Step 3: Implement the service and register it**

`builder.Services.AddHttpClient<IZitadelPasskeyAdminService, ZitadelPasskeyAdminService>()` with the same resilience policy name pattern used by the other ZITADEL clients. Non-2xx: 401/403/5xx → `ServiceUnavailableException(..., "identity_provider_unavailable")`; malformed 2xx JSON → same. Log at Error for upstream faults, Warning for a 404 on delete.

- [ ] **Step 4: Re-run**

Run: same command. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src/TaskTapAPI.Application/Services/Identity/IZitadelPasskeyAdminService.cs \
        src/TaskTapAPI.Application/Services/Identity/ZitadelPasskeyAdminService.cs \
        src/TaskTapAPI.Api/Program.cs \
        tests/TaskTapAPI.Tests/Services/ZitadelPasskeyAdminServiceTests.cs
git commit -m "feat(identity): add the ZITADEL passkey administration service"
```

---

### Task 4: Session service passkey sign-in (API repo)

**Files:**
- Modify: `src/TaskTapAPI.Application/Services/Identity/IZitadelSessionService.cs` (replace the draft methods)
- Modify: `src/TaskTapAPI.Application/Services/Identity/ZitadelSessionService.cs`
- Test: `tests/TaskTapAPI.Tests/Services/ZitadelSessionServiceTests.cs`

**Interfaces:**
- Consumes: Task 2's `EffectiveWebAuthnRpId`, Task 3's `IZitadelPasskeyAdminService.ListAsync`.
- Produces:
  - `record PasskeyLoginChallenge(string SessionId, string SessionToken, JsonElement PublicKeyCredentialRequestOptions)`
  - `Task<PasskeyLoginChallenge> StartPasskeyLoginAsync(string authRequestId, string loginName, CancellationToken ct = default)`
  - `Task<string> CompletePasskeyLoginAsync(string authRequestId, string sessionId, string sessionToken, JsonElement credentialAssertionData, CancellationToken ct = default)`

- [ ] **Step 1: Write the failing tests**

Extend the existing scripted-handler suite; `BuildService` gains a fake passkey admin whose `ListAsync` is scripted per test.

```csharp
StartPasskeyLoginAsync_UsesTheConfiguredRpIdAndRequestsAChallenge
  // POST /v2/sessions body: challenges.webAuthN.domain == "auth.tasktap.test",
  //   userVerificationRequirement == "USER_VERIFICATION_REQUIREMENT_REQUIRED"
  // returns sessionId/sessionToken/publicKeyCredentialRequestOptions from the response

StartPasskeyLoginAsync_UnknownEmail_ThrowsNoPasskeyRegistered
  // identity lookup returns null; no HTTP call; code == "no_passkey_registered"

StartPasskeyLoginAsync_UserWithoutPasskeys_ThrowsNoPasskeyRegistered
  // ListAsync returns empty; no CreateSession call; same code

StartPasskeyLoginAsync_MissingChallenge_ThrowsServiceUnavailable
StartPasskeyLoginAsync_UpstreamFault_ThrowsServiceUnavailable

CompletePasskeyLoginAsync_PatchesTheSessionThenReturnsTheCode
  // PATCH /v2/sessions/sess-1 body checks.webAuthN.credentialAssertionData is the supplied JSON
  // then POST /v2/oidc/auth_requests/authreq-1 with the returned sessionToken

CompletePasskeyLoginAsync_RejectedAssertion_ThrowsPasskeyVerificationFailed
  // PATCH 400 -> DomainRuleException code == "passkey_verification_failed"

CompletePasskeyLoginAsync_CallbackPreconditionFailed_ThrowsAdditionalFactorRequired
CompletePasskeyLoginAsync_NoSessionToken_ThrowsServiceUnavailable
```

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/TaskTapAPI.Tests/TaskTapAPI.Tests.csproj --filter "FullyQualifiedName~ZitadelSessionServiceTests"`
Expected: compile failure against the draft signatures.

- [ ] **Step 3: Implement**

`StartPasskeyLoginAsync`: resolve `loginName` → userId (`_identityAdmin.GetUserIdByEmailAsync`); null → `DomainRuleException("Nessuna passkey...", "no_passkey_registered")`; `ListAsync` empty → same code; `POST v2/sessions` with the challenge; read `challenges.webAuthN.publicKeyCredentialRequestOptions`; missing → 503.

`CompletePasskeyLoginAsync`: `PATCH v2/sessions/{id}` with `{sessionId, sessionToken, checks:{webAuthN:{credentialAssertionData}}}`; non-2xx user-fault → `DomainRuleException(..., "passkey_verification_failed")`; upstream fault → 503; then reuse the existing `CreateCallbackAsync` (which already maps 412 to `additional_factor_required`).

Remove the draft's `rpId` parameter entirely.

- [ ] **Step 4: Re-run**

Run: same command. Expected: all pass, including the pre-existing password tests.

- [ ] **Step 5: Commit**

```bash
git add src/TaskTapAPI.Application/Services/Identity/IZitadelSessionService.cs \
        src/TaskTapAPI.Application/Services/Identity/ZitadelSessionService.cs \
        tests/TaskTapAPI.Tests/Services/ZitadelSessionServiceTests.cs
git commit -m "feat(auth): passkey session start/complete with a server-derived RP ID"
```

---

### Task 5: MobileAuth passkey endpoints (API repo)

**Files:**
- Modify: `src/TaskTapAPI.Api/Controllers/MobileAuthController.cs`
- Test: `tests/TaskTapAPI.Tests/Controllers/MobileAuthPasskeyHttpTests.cs` (create)

**Interfaces:**
- Consumes: Task 3 and Task 4 services.
- Produces the HTTP surface from the spec §9: `passkey/login/start`, `passkey/login/complete`, `passkey/register/start`, `passkey/register/complete`, `GET passkey`, `DELETE passkey/{id}`.

- [ ] **Step 1: Write the failing HTTP tests**

Follow `tests/TaskTapAPI.Tests/Controllers/ReportTemplateConfigHttpTests.cs`: `[Collection(PostgresCollection.Name)]`, `AuthenticatedApiFactory`, and replace the two ZITADEL services in `WithWebHostBuilder(b => b.ConfigureTestServices(...))` with fakes that record their arguments.

```csharp
Login_RemainsAnonymous            // no bearer; still reaches the password service (regression guard)
RegisterStart_WithoutABearer_Returns401
RegisterStart_PassesTheTokenSubjectAndIgnoresAnyUserIdInTheBody
LoginStart_MapsNoPasskeyRegisteredTo400WithTheCode
LoginComplete_ReturnsTheAuthorizationCode
List_ReturnsTheCallersPasskeys
Delete_Returns204
```

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/TaskTapAPI.Tests/TaskTapAPI.Tests.csproj --filter "FullyQualifiedName~MobileAuthPasskeyHttpTests"`
Expected: 404s / compile failure.

- [ ] **Step 3: Implement the endpoints**

- Remove `RpId` from the request models and the draft `passkey/start|complete` routes.
- `MobileAuthController` currently carries a class-level `[AllowAnonymous]`. **`[Authorize]` on an action inside an `[AllowAnonymous]` controller is ignored**, so remove the class attribute and put `[AllowAnonymous]` on `Login`, `StartPasskey`, `CompletePasskey` and the two retired 410 actions; put `[Authorize]` on register/list/delete. The `Login_RemainsAnonymous` test is the guard that password login did not get locked behind a bearer.
- On the authenticated actions resolve the user from `HttpContext.User.FindFirst("sub")`; missing → 401.
- Login endpoints stay anonymous and on the controller's existing rate limiter.
- Let `DomainRuleException`/`ServiceUnavailableException` reach the error middleware (it already emits `{code, detail}`), so the controller contains no mapping code.
- Audit best-effort: `auth.login.passkey`, `auth.passkey.register`, `auth.passkey.delete`, with tenant/user when resolvable.

- [ ] **Step 4: Re-run**

Run: same command. Expected: all pass. (Postgres-gated tests are skipped locally without a Postgres fixture; note which were skipped.)

- [ ] **Step 5: Commit**

```bash
git add src/TaskTapAPI.Api/Controllers/MobileAuthController.cs \
        tests/TaskTapAPI.Tests/Controllers/MobileAuthPasskeyHttpTests.cs
git commit -m "feat(auth): passkey login and enrolment endpoints"
```

---

### Task 6: OpenAPI snapshot (API repo)

**Files:**
- Modify: `docs/api/openapi.snapshot.json`
- Modify: `mobile/test/contract/openapi.snapshot.json` (copied)

- [ ] **Step 1: Regenerate**

```bash
UPDATE_OPENAPI_SNAPSHOT=1 dotnet test tests/TaskTapAPI.Tests/TaskTapAPI.Tests.csproj \
  --filter "FullyQualifiedName~OpenApiSnapshotTests"
```

- [ ] **Step 2: Verify the gate is green without the variable**

Run the same command without `UPDATE_OPENAPI_SNAPSHOT`. Expected: pass, and the snapshot diff contains only the six new passkey operations.

- [ ] **Step 3: Sync the mobile copy**

```bash
cp docs/api/openapi.snapshot.json ../mobile/test/contract/openapi.snapshot.json
```

(Execute from the API worktree; adjust the relative path to the mobile worktree.)

- [ ] **Step 4: Commit both**

```bash
git add docs/api/openapi.snapshot.json
git commit -m "docs(api): refresh the OpenAPI snapshot for passkey auth"
# in the mobile worktree:
git add test/contract/openapi.snapshot.json
git commit -m "chore(contract): sync the OpenAPI snapshot"
```

---

### Task 7: Passkey support gate and failure types (mobile repo)

**Files:**
- Modify: `pubspec.yaml` (already has `passkeys: ^2.11.0`; keep it)
- Create: `lib/core/security/passkey_support.dart`
- Modify: `lib/domain/auth/auth_failure.dart`
- Test: `test/core/security/passkey_support_test.dart` (create)
- Test: `test/data/auth/auth_failure_test.dart` (extend)

**Interfaces:**
- Produces: `class PasskeySupport { Future<bool> isAvailable(); }`, `final passkeySupportedProvider = FutureProvider<bool>(...)`, and `AuthFailure` cases `PasskeyNotRegistered`, `PasskeyUnavailable`, `PasskeyCancelled`.

- [ ] **Step 1: Write the failing tests**

```dart
// passkey_support_test.dart
test('android is available only with support and a verifying authenticator', ...)
  // fake a GetAvailability result with hasPasskeySupport true / false
test('ios requires support and biometrics', ...)

// auth_failure_test.dart
test('passkey messages are the exact Italian copy', () {
  expect(authFailureMessage(const PasskeyNotRegistered()),
    'Nessuna passkey disponibile. Accedi con la password; potrai attivarla dalle impostazioni dopo l\'accesso.');
  expect(authFailureMessage(const PasskeyUnavailable()),
    'Questo dispositivo non supporta le passkey.');
});
```

`PasskeySupport` must be injectable (constructor takes a `PasskeyAuthenticator`-like availability source) so tests never touch platform channels.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/core/security/passkey_support_test.dart test/data/auth/auth_failure_test.dart`
Expected: failures for the missing class/cases.

- [ ] **Step 3: Implement**

`PasskeySupport.isAvailable()`: `kIsWeb` → false; `Platform.isAndroid` → `getAvailability().android()` and require `hasPasskeySupport && isUserVerifyingPlatformAuthenticatorAvailable`; `Platform.isIOS` → `getAvailability().iOS()` and require `hasPasskeySupport && hasBiometrics`; other platforms → false. Any platform exception → false.

Add the three failure cases and their messages; `PasskeyCancelled` maps to an empty string (never rendered).

- [ ] **Step 4: Re-run**

Run: same command. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/security/passkey_support.dart lib/domain/auth/auth_failure.dart \
        test/core/security/passkey_support_test.dart test/data/auth/auth_failure_test.dart
git commit -m "feat(auth): add the passkey availability gate and failure types"
```

---

### Task 8: Repository passkey sign-in (mobile repo)

**Files:**
- Modify: `lib/domain/auth/i_auth_repository.dart` (declaration only; remove the draft default body)
- Modify: `lib/data/auth/zitadel_auth_repository.dart` (replace the draft implementation)
- Test: `test/data/auth/passkey_sign_in_test.dart` (create)

**Interfaces:**
- Consumes: API `passkey/login/start|complete`; Task 7 failure types.
- Produces: `Future<({AuthUser? user, AuthFailure? failure})> signInWithPasskey(String loginName)`.

- [ ] **Step 1: Write the failing tests**

Reuse the `MockAppAuth`/`MockSecureStorage`/`MockDio` setup from `test/data/auth/zitadel_auth_repository_test.dart`. Script the two POSTs and the token exchange.

```dart
test('unwraps publicKey before authenticating and sends toJson() to complete')
  // start response: {'sessionId':'s1','sessionToken':'st','publicKeyCredentialRequestOptions':{'publicKey':{...}}}
  // assert the captured data has 'credentialAssertionData' with nested 'response'
test('no_passkey_registered maps to PasskeyNotRegistered')
test('passkey_verification_failed maps to UnknownAuthError with the code')
test('additional_factor_required maps to AdditionalFactorRequired')
test('a cancelled sheet maps to PasskeyCancelled')
test('missing publicKey in the options maps to UnknownAuthError, never throws')
test('a domain-not-associated platform error maps to PasskeyUnavailable')
```

The authenticator must be injectable (constructor parameter defaulting to `PasskeyAuthenticator()`), so tests supply a fake that returns a known `AuthenticateResponseType` or throws `PasskeyAuthCancelledException`.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/data/auth/passkey_sign_in_test.dart`
Expected: failures.

- [ ] **Step 3: Implement**

Same shape as `signInWithPassword`: capture `authRequestId`, POST `/api/MobileAuth/passkey/login/start` with `{authRequestId, loginName}` (no `rpId`), read `publicKeyCredentialRequestOptions['publicKey']`, `AuthenticateRequestType.fromJson`, `authenticate`, POST `/api/MobileAuth/passkey/login/complete` with `credentialAssertionData: assertion.toJson()`, then the existing `_appAuth.token` + `_fromTokens` + persist + emit path. Map exceptions per the spec.

- [ ] **Step 4: Re-run**

Run: same command, then `flutter test test/data/auth/` to confirm no regressions.
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/auth/i_auth_repository.dart lib/data/auth/zitadel_auth_repository.dart \
        test/data/auth/passkey_sign_in_test.dart
git commit -m "feat(auth): native passkey sign-in in the repository"
```

---

### Task 9: Passkey enrolment client (mobile repo)

**Files:**
- Create: `lib/data/auth/passkey_enroller.dart`
- Test: `test/data/auth/passkey_enroller_test.dart` (create)

**Interfaces:**
- Consumes: `dioProvider`, Task 7 failure types, the `passkeys` authenticator.
- Produces: `record PasskeySummary(String id, String name)`, `class PasskeyEnroller` with `Future<List<PasskeySummary>> list()`, `Future<({bool ok, AuthFailure? failure})> enrol({required String name})`, `Future<({bool ok, AuthFailure? failure})> remove(String id)`; `final passkeyEnrollerProvider = Provider<PasskeyEnroller>(...)` reading `dioProvider`.

- [ ] **Step 1: Write the failing tests**

```dart
test('enrol unwraps publicKey, registers, and posts publicKeyCredential')
test('enrol offline returns NetworkError and does not claim success')
test('enrol complete failure returns UnknownAuthError')
test('cancelled registration is ok=false, failure=null')
test('list parses id and name')
test('remove issues DELETE for the id')
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/data/auth/passkey_enroller_test.dart`
Expected: failures.

- [ ] **Step 3: Implement**

`enrol`: POST `/api/MobileAuth/passkey/register/start`, unwrap `publicKeyCredentialCreationOptions['publicKey']`, `RegisterRequestType.fromJson`, `PasskeyAuthenticator.register`, POST `/api/MobileAuth/passkey/register/complete` with `{passkeyId, publicKeyCredential: response.toJson(), passkeyName: name}`. `list`/`remove` hit `GET /api/MobileAuth/passkey` and `DELETE /api/MobileAuth/passkey/{id}`. Map `DioException`/passkey exceptions to the failure types; cancellation returns `(ok: false, failure: null)`.

- [ ] **Step 4: Re-run**

Run: same command. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/auth/passkey_enroller.dart test/data/auth/passkey_enroller_test.dart
git commit -m "feat(auth): passkey enrolment client"
```

---

### Task 10: Login screen passkey button (mobile repo)

**Files:**
- Modify: `lib/presentation/providers/auth_providers.dart` (cancellation is a no-op)
- Modify: `lib/presentation/screens/login/login_screen.dart` (replace the draft button)
- Test: `test/presentation/screens/login_screen_test.dart` (extend)
- Test: `test/presentation/providers/auth_providers_test.dart` (extend)

**Interfaces:**
- Consumes: Task 7 `passkeySupportedProvider`, Task 8 `signInWithPasskey`.

- [ ] **Step 1: Write the failing tests**

```dart
// auth_providers_test.dart
test('a cancelled passkey attempt clears the spinner and shows no error')
test('PasskeyNotRegistered is surfaced as a failure')

// login_screen_test.dart
testWidgets('the passkey button is hidden when the platform has no support')
testWidgets('the passkey button is visible when supported')
testWidgets('double tapping the passkey button starts one attempt')
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/presentation/providers/auth_providers_test.dart test/presentation/screens/login_screen_test.dart`
Expected: failures.

- [ ] **Step 3: Implement**

`LoginNotifier.signInWithPasskey`: on `PasskeyCancelled`, set `const LoginState()` (no failure); otherwise current behaviour. Login screen: watch `passkeySupportedProvider`; render an `OutlinedButton` labelled **Accedi con passkey** only when true and `!isLoading`; no `TextInput.finishAutofillContext()` on the passkey path.

- [ ] **Step 4: Re-run**

Run: same command. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/providers/auth_providers.dart lib/presentation/screens/login/login_screen.dart \
        test/presentation/providers/auth_providers_test.dart test/presentation/screens/login_screen_test.dart
git commit -m "feat(auth): opt-in passkey button on the login screen"
```

---

### Task 11: Passkey settings section (mobile repo)

**Files:**
- Create: `lib/features/altro/passkey_settings_section.dart`
- Modify: `lib/features/altro/impostazioni_screen.dart` (insert the section near the biometric switch, ~line 215)
- Test: `test/features/altro/passkey_settings_section_test.dart` (create)

**Interfaces:**
- Consumes: Task 9 `passkeyEnrollerProvider`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('shows the personal-device warning')
testWidgets('enrolling success refreshes the list and toasts')
testWidgets('a failed enrolment shows an error and leaves the list unchanged')
testWidgets('remove asks for confirmation and calls remove')
testWidgets('section is disabled with a reason when unsupported')
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/features/altro/passkey_settings_section_test.dart`
Expected: failures.

- [ ] **Step 3: Implement**

A `Card` titled **Accesso con passkey** with the warning copy from the spec, the list of passkeys (name) with a **Rimuovi passkey** action behind `confirmDeleteDialog`, and a primary **Attiva accesso con passkey** action that calls `enrol(name: 'TaskTap su questo dispositivo')`. Toast **Passkey attivata.** on success.

- [ ] **Step 4: Re-run**

Run: same command. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/altro/passkey_settings_section.dart lib/features/altro/impostazioni_screen.dart \
        test/features/altro/passkey_settings_section_test.dart
git commit -m "feat(settings): enrol and remove passkeys"
```

---

### Task 12: Platform configuration (mobile repo)

**Files:**
- Modify: `ios/Runner/Runner.entitlements`
- Verify: `android/app/build.gradle.kts` (`minSdk >= 23`)

- [ ] **Step 1: Add the associated domain**

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>webcredentials:auth.tasktap.it</string>
</array>
```

- [ ] **Step 2: Confirm the Android floor**

`minSdk = flutter.minSdkVersion` must resolve to ≥ 23. If the Flutter default is lower, set it explicitly to 23.

- [ ] **Step 3: Verify the build still configures**

```bash
flutter build ios --config-only --no-codesign
flutter build apk --debug
```

Expected: both succeed. (The iOS capability must also be enabled for the bundle id in the Apple Developer portal; CI's provisioning profile must include it. That is an ops action, recorded in the PR.)

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/Runner.entitlements android/app/build.gradle.kts
git commit -m "chore(ios/android): associate the app with the passkey relying party"
```

---

### Task 13: Device verification (manual, both repos)

- [ ] **Step 1: Android** — Play-enabled emulator with screen lock and a Google account, plus a physical device.

Enrol → sign out → sign in with passkey → remove in settings → sign-in shows **Nessuna passkey disponibile**. Repeat once with a Play-installed build.

- [ ] **Step 2: iOS** — simulator with enrolled Face ID and a physical device.

Same sequence; confirm the sheet offers the passkey (not a security-key-only sheet).

- [ ] **Step 3: Failure drills**

- Cancel the sheet: no banner, form usable.
- Airplane mode at `register/complete`: error toast, list unchanged.
- Remove the passkey in ZITADEL Console, then try signing in: **Nessuna passkey disponibile**.
- Temporarily clear the Native App Links config: generic error, log line names the association problem, no loop.

- [ ] **Step 4: Record the results** in the mobile PR description.
