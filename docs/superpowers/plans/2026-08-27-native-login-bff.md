# Native Password Login via a Thin BFF — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the system-browser Zitadel login hand-off with an in-app password form for the common case, backed by a thin backend proxy for the two calls that structurally require a privileged Zitadel credential.

**Architecture:** Mobile starts the OAuth authorization request and does the token exchange itself (public client, PKCE — unchanged from today). A new backend endpoint submits the password to Zitadel's Session API and links the resulting session to the pending auth request, returning an authorization code. The existing browser-based `signIn()` stays as the permanent fallback for forgot-password, unsupported MFA, and unexpected errors.

**Tech Stack:** Flutter/Dart (mobile, `flutter_appauth`, `dio`, `flutter_riverpod`, new: `crypto` for PKCE), .NET (backend, `TaskTapAPI.Api`/`TaskTapAPI.Application`, existing `HttpClient`/`IOptions` DI conventions).

**Spec:** `mobile/docs/superpowers/specs/2026-08-27-native-login-bff-design.md`

## Global Constraints

- Password only. MFA/passkey is out of scope — any session Zitadel reports as needing more than a password falls back to the existing browser flow, never a native error dead-end.
- The existing `signIn()` (browser flow) and everything downstream of `_fromTokens` (token storage, offline restore, refresh) is untouched. Every new mobile method is additive to `IAuthRepository`.
- Backend: reuse `MobileAuthController`'s existing (currently 410) `POST api/MobileAuth/login` route — do not add a new route.
- Backend: reuse the existing `DomainException` hierarchy (`TaskTapAPI.Core.Exceptions`) and the existing `AddHttpClient<TInterface, TImpl>().AddHttpMessageHandler<ZitadelForwardingHandler>().AddResiliencePolicies(name)` registration pattern — do not invent a new error-response shape or a new HTTP client setup style.
- Backend work happens in an isolated git worktree off `master` (per this project's standing rule — `develop` is stale relative to `master`), never the shared checkout. Set it up with the `superpowers:using-git-worktrees` skill before Task 2.
- Mobile work happens directly in `/mnt/d/AEA/Sviluppi/TaskTap/mobile` on branch `develop`.
- Every task ends green: `dart analyze`/`flutter test` (mobile, run from the WSL-native scratch copy per this project's own testing convention) or `dotnet test` (backend) before its commit.

---

## Task 1: Zitadel instance prerequisite (manual — not code)

This task has no code and cannot be completed by an implementing engineer or agent — it requires console access to the live Zitadel tenant, which only the project owner has. Everything from Task 2 onward depends on its output (a PAT string) existing in configuration.

**Steps (Zitadel console):**

1. Create a new machine user (service account): `/ui/console/users/create-machine`. Suggested name: `tasktap-login-client`. This must be a **separate** machine user from whichever one backs the existing `Zitadel:ServiceAccountKeyPath`/`ServiceAccountKeyJson` (Management API) — `IAM_LOGIN_CLIENT` is an instance-wide privilege that can finalize login for any user on the instance, and should not be layered onto the account that already does day-to-day user provisioning.
2. Generate a Personal Access Token for it: on the user's detail page, `+ New` under Personal Access Tokens. Copy the token value now — Zitadel shows it once.
3. Grant the **"Instance Login Client"** role (internally `IAM_LOGIN_CLIENT`) to this machine user at the instance level: `/ui/console/instance/members` → add member → select the machine user → assign `IAM_LOGIN_CLIENT`.
4. Store the PAT as a new secret alongside the existing `Zitadel:ServiceAccountKeyPath`/`ServiceAccountKeyJson` config (wherever those are injected in this deployment — e.g. an env var `ZITADEL_LOGIN_CLIENT_PAT`, mapped to `Zitadel:LoginClientPersonalAccessToken` in configuration). Do not commit the raw value anywhere.

**Verification (run once the PAT exists, from any machine that can reach the Zitadel instance):**

```bash
curl -s -X POST "https://<your-zitadel-issuer>/v2/sessions" \
  -H "Authorization: Bearer <the PAT>" \
  -H "Content-Type: application/json" \
  -d '{"checks":{"user":{"loginName":"<a real test user login name>"}}}'
```

Expected: HTTP 200 with a JSON body containing `sessionId` and `sessionToken`. If this 403s, the role grant (step 3) didn't take — re-check it in the console. If the response shape differs from `{sessionId, sessionToken, ...}` (field names, casing), note the actual shape now — Task 3's tests must match reality, not this plan's inference from Zitadel's docs/proto.

- [ ] **Step 1: Complete the four console steps above and the curl verification.** Confirm the PAT works and record the exact `POST /v2/sessions` response shape (for Task 3).

---

## Task 2: Backend — Session-login option + worktree setup

**Files:**
- Modify: `src/TaskTapAPI.Application/Services/Identity/ZitadelOptions.cs`
- Test: `tests/TaskTapAPI.Tests/Services/ZitadelOptionsTests.cs` (create if it doesn't exist; check first)

**Interfaces:**
- Produces: `ZitadelOptions.LoginClientPersonalAccessToken` (string, empty default) — consumed by Task 3's `ZitadelSessionService`.

- [ ] **Step 1: Set up the isolated worktree.** Use the `superpowers:using-git-worktrees` skill to create a worktree for this work, branched off `master` (not `develop`) in the backend repo at `/mnt/d/AEA/Sviluppi/TaskTap`. Do all remaining backend tasks inside that worktree.

- [ ] **Step 2: Check for an existing `ZitadelOptionsTests.cs`.**

Run: `find tests -iname "ZitadelOptionsTests.cs"` from the worktree root.

If it exists, read it and follow its existing style for the next step. If not, create it fresh following the pattern below.

- [ ] **Step 3: Add the field to `ZitadelOptions`.**

```csharp
/// <summary>
/// Personal Access Token for a machine user holding the instance-level <c>IAM_LOGIN_CLIENT</c>
/// role. Distinct from <see cref="ServiceAccountKeyPath"/>/<see cref="ServiceAccountKeyJson"/>
/// (the Management API service account) — this is a separate, more privileged identity used
/// only to finalize native login sessions (<see cref="Identity.ZitadelSessionService"/>). Never
/// log this value.
/// </summary>
public string LoginClientPersonalAccessToken { get; set; } = string.Empty;
```

Add it to `ZitadelOptions.cs` alongside the existing `ServiceAccountKeyPath`/`ServiceAccountKeyJson` properties.

- [ ] **Step 4: Write a test confirming the option binds from configuration.**

```csharp
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using TaskTapAPI.Application.Services.Identity;

namespace TaskTapAPI.Tests.Services;

public class ZitadelOptionsTests
{
    [Fact]
    public void LoginClientPersonalAccessToken_BindsFromConfiguration()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Zitadel:LoginClientPersonalAccessToken"] = "pat-value-123",
            })
            .Build();

        var options = new ZitadelOptions();
        config.GetSection("Zitadel").Bind(options);

        options.LoginClientPersonalAccessToken.Should().Be("pat-value-123");
    }
}
```

- [ ] **Step 5: Run the test.**

Run: `dotnet test --filter ZitadelOptionsTests`
Expected: PASS.

- [ ] **Step 6: Commit.**

```bash
git add src/TaskTapAPI.Application/Services/Identity/ZitadelOptions.cs tests/TaskTapAPI.Tests/Services/ZitadelOptionsTests.cs
git commit -m "Add Zitadel login-client PAT option"
```

---

## Task 3: Backend — `ZitadelSessionService`

**Files:**
- Create: `src/TaskTapAPI.Application/Services/Identity/IZitadelSessionService.cs`
- Create: `src/TaskTapAPI.Application/Services/Identity/ZitadelSessionService.cs`
- Test: `tests/TaskTapAPI.Tests/Services/ZitadelSessionServiceTests.cs`

**Interfaces:**
- Consumes: `ZitadelOptions.LoginClientPersonalAccessToken` (Task 2), `ZitadelOptions.ApiBaseUrl` (existing).
- Produces: `IZitadelSessionService.LoginAsync(string authRequestId, string loginName, string password, CancellationToken ct)` returning `Task<string>` (the authorization `code`) — consumed by Task 4's controller. Throws `DomainRuleException` (code `"invalid_credentials"` or `"additional_factor_required"`) or `ServiceUnavailableException` (code `"identity_provider_unavailable"`) on failure — both already defined in `TaskTapAPI.Core.Exceptions`.

- [ ] **Step 1: Write the interface.**

```csharp
namespace TaskTapAPI.Application.Services.Identity;

/// <summary>
/// Finalizes a native (in-app) password login against Zitadel's Session API — the
/// two calls a mobile client cannot make itself because they require the
/// instance-level <c>IAM_LOGIN_CLIENT</c> credential (see
/// <see cref="ZitadelOptions.LoginClientPersonalAccessToken"/>'s own doc comment).
/// </summary>
public interface IZitadelSessionService
{
    /// <summary>
    /// Submits <paramref name="loginName"/>/<paramref name="password"/> to Zitadel and links the
    /// resulting session to <paramref name="authRequestId"/> (the pending OAuth authorization
    /// request the mobile client already started). Returns the authorization code the mobile
    /// client exchanges for tokens at Zitadel's own token endpoint.
    /// </summary>
    Task<string> LoginAsync(string authRequestId, string loginName, string password, CancellationToken ct = default);
}
```

- [ ] **Step 2: Write the failing tests.**

```csharp
using System.Net;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TaskTapAPI.Application.Services.Identity;
using TaskTapAPI.Core.Exceptions;

namespace TaskTapAPI.Tests.Services;

public class ZitadelSessionServiceTests
{
    private sealed class RecordedRequest(HttpRequestMessage request)
    {
        public string Method { get; } = request.Method.Method;
        public string Url { get; } = request.RequestUri?.ToString() ?? string.Empty;
        public string? AuthHeader { get; } = request.Headers.Authorization?.ToString();
        public string? Body { get; } =
            request.Content is null ? null : request.Content.ReadAsStringAsync().GetAwaiter().GetResult();
    }

    /// <summary>Responds by URL segment so a test can script the three-call sequence
    /// (CreateSession → SetSession → CreateCallback) independently.</summary>
    private sealed class ScriptedHandler : HttpMessageHandler
    {
        public List<RecordedRequest> Requests { get; } = [];
        public Func<RecordedRequest, HttpResponseMessage>? Respond;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var recorded = new RecordedRequest(request);
            Requests.Add(recorded);
            var response = Respond?.Invoke(recorded)
                ?? new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}") };
            return Task.FromResult(response);
        }
    }

    private static ZitadelSessionService BuildService(ScriptedHandler handler) =>
        new(new HttpClient(handler),
            Options.Create(new ZitadelOptions
            {
                Url = "https://auth.tasktap.test",
                LoginClientPersonalAccessToken = "pat-123",
            }),
            NullLogger<ZitadelSessionService>.Instance);

    [Fact]
    public async Task LoginAsync_HappyPath_ReturnsCodeFromCallbackUrl()
    {
        var handler = new ScriptedHandler
        {
            Respond = r => r.Url switch
            {
                var u when u.EndsWith("/v2/sessions") && r.Method == "POST" =>
                    new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent("""{"sessionId":"sess-1","sessionToken":"tok-1"}"""),
                    },
                var u when u.Contains("/v2/sessions/sess-1") && r.Method == "PATCH" =>
                    new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent("""{"sessionToken":"tok-2"}"""),
                    },
                var u when u.Contains("/v2/oidc/auth_requests/authreq-1") =>
                    new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(
                            """{"callbackUrl":"it.tasktap.app://callback?code=abc123&state=xyz"}"""),
                    },
                _ => new HttpResponseMessage(HttpStatusCode.NotFound),
            },
        };
        var service = BuildService(handler);

        var code = await service.LoginAsync("authreq-1", "tech@tasktap.io", "correct-password");

        code.Should().Be("abc123");

        // All three privileged calls carry the login-client PAT, not the request's own tokens.
        handler.Requests.Should().AllSatisfy(r => r.AuthHeader.Should().Be("Bearer pat-123"));

        var createSession = handler.Requests[0];
        using var createBody = JsonDocument.Parse(createSession.Body!);
        createBody.RootElement.GetProperty("checks").GetProperty("user").GetProperty("loginName")
            .GetString().Should().Be("tech@tasktap.io");

        var setSession = handler.Requests[1];
        setSession.Url.Should().EndWith("/v2/sessions/sess-1");
        using var setBody = JsonDocument.Parse(setSession.Body!);
        setBody.RootElement.GetProperty("checks").GetProperty("password").GetProperty("password")
            .GetString().Should().Be("correct-password");

        var callback = handler.Requests[2];
        using var callbackBody = JsonDocument.Parse(callback.Body!);
        callbackBody.RootElement.GetProperty("session").GetProperty("sessionId").GetString().Should().Be("sess-1");
        callbackBody.RootElement.GetProperty("session").GetProperty("sessionToken").GetString().Should().Be("tok-2");
    }

    [Fact]
    public async Task LoginAsync_WrongPassword_ThrowsInvalidCredentials()
    {
        var handler = new ScriptedHandler
        {
            Respond = r => r.Url switch
            {
                var u when u.EndsWith("/v2/sessions") && r.Method == "POST" =>
                    new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent("""{"sessionId":"sess-1","sessionToken":"tok-1"}"""),
                    },
                var u when u.Contains("/v2/sessions/sess-1") && r.Method == "PATCH" =>
                    new HttpResponseMessage(HttpStatusCode.BadRequest)
                    {
                        Content = new StringContent("""{"message":"invalid password"}"""),
                    },
                _ => new HttpResponseMessage(HttpStatusCode.NotFound),
            },
        };
        var service = BuildService(handler);

        var act = () => service.LoginAsync("authreq-1", "tech@tasktap.io", "wrong-password");

        var ex = await act.Should().ThrowAsync<DomainRuleException>();
        ex.Which.Code.Should().Be("invalid_credentials");
    }

    [Fact]
    public async Task LoginAsync_UnknownLoginName_ThrowsInvalidCredentials()
    {
        var handler = new ScriptedHandler
        {
            Respond = r => new HttpResponseMessage(HttpStatusCode.NotFound)
            {
                Content = new StringContent("""{"message":"user not found"}"""),
            },
        };
        var service = BuildService(handler);

        var act = () => service.LoginAsync("authreq-1", "nobody@tasktap.io", "whatever");

        var ex = await act.Should().ThrowAsync<DomainRuleException>();
        ex.Which.Code.Should().Be("invalid_credentials");
    }

    [Fact]
    public async Task LoginAsync_PasswordAcceptedButCallbackRejected_ThrowsAdditionalFactorRequired()
    {
        var handler = new ScriptedHandler
        {
            Respond = r => r.Url switch
            {
                var u when u.EndsWith("/v2/sessions") && r.Method == "POST" =>
                    new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent("""{"sessionId":"sess-1","sessionToken":"tok-1"}"""),
                    },
                var u when u.Contains("/v2/sessions/sess-1") && r.Method == "PATCH" =>
                    new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent("""{"sessionToken":"tok-2"}"""),
                    },
                var u when u.Contains("/v2/oidc/auth_requests/authreq-1") =>
                    new HttpResponseMessage(HttpStatusCode.PreconditionFailed)
                    {
                        Content = new StringContent("""{"message":"further verification required"}"""),
                    },
                _ => new HttpResponseMessage(HttpStatusCode.NotFound),
            },
        };
        var service = BuildService(handler);

        var act = () => service.LoginAsync("authreq-1", "tech@tasktap.io", "correct-password");

        var ex = await act.Should().ThrowAsync<DomainRuleException>();
        ex.Which.Code.Should().Be("additional_factor_required");
    }

    [Fact]
    public async Task LoginAsync_ZitadelUnreachable_ThrowsServiceUnavailable()
    {
        var handler = new ScriptedHandler
        {
            Respond = _ => throw new HttpRequestException("connection refused"),
        };
        var service = BuildService(handler);

        var act = () => service.LoginAsync("authreq-1", "tech@tasktap.io", "correct-password");

        var ex = await act.Should().ThrowAsync<ServiceUnavailableException>();
        ex.Which.Code.Should().Be("identity_provider_unavailable");
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail.**

Run: `dotnet test --filter ZitadelSessionServiceTests`
Expected: FAIL (compile error — `ZitadelSessionService` doesn't exist yet).

- [ ] **Step 4: Write the implementation.**

```csharp
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using TaskTapAPI.Core.Exceptions;

namespace TaskTapAPI.Application.Services.Identity;

/// <inheritdoc cref="IZitadelSessionService"/>
public class ZitadelSessionService : IZitadelSessionService
{
    private readonly HttpClient _http;
    private readonly ZitadelOptions _options;
    private readonly ILogger<ZitadelSessionService> _logger;

    private static readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web);

    public ZitadelSessionService(HttpClient http, IOptions<ZitadelOptions> options, ILogger<ZitadelSessionService> logger)
    {
        _http = http;
        _options = options.Value;
        _logger = logger;
        _http.BaseAddress = new Uri(_options.ApiBaseUrl);
    }

    public async Task<string> LoginAsync(string authRequestId, string loginName, string password, CancellationToken ct = default)
    {
        var (sessionId, _) = await CreateSessionAsync(loginName, ct);
        var sessionToken = await SetPasswordAsync(sessionId, password, ct);
        return await CreateCallbackAsync(authRequestId, sessionId, sessionToken, ct);
    }

    private async Task<(string SessionId, string SessionToken)> CreateSessionAsync(string loginName, CancellationToken ct)
    {
        var body = new { checks = new { user = new { loginName } } };
        var response = await SendAsync(HttpMethod.Post, "v2/sessions", body, ct);

        if (!response.IsSuccessStatusCode)
        {
            // Any failure here (unknown loginName, malformed request) reads to the user exactly
            // like a wrong password would — Zitadel does not distinguish "no such account" from
            // "wrong credentials" in its own hosted UI either, on purpose.
            _logger.LogWarning("Zitadel CreateSession failed {Status} for login attempt", response.StatusCode);
            throw new DomainRuleException("Credenziali non valide.", "invalid_credentials");
        }

        var json = await ReadJsonAsync(response, ct);
        var sessionId = json.RootElement.GetProperty("sessionId").GetString()
            ?? throw new ServiceUnavailableException("Accesso non disponibile al momento.", "identity_provider_unavailable");
        var sessionToken = json.RootElement.GetProperty("sessionToken").GetString() ?? string.Empty;
        return (sessionId, sessionToken);
    }

    private async Task<string> SetPasswordAsync(string sessionId, string password, CancellationToken ct)
    {
        var body = new { checks = new { password = new { password } } };
        var response = await SendAsync(HttpMethod.Patch, $"v2/sessions/{Uri.EscapeDataString(sessionId)}", body, ct);

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogWarning("Zitadel SetSession (password check) failed {Status}", response.StatusCode);
            throw new DomainRuleException("Credenziali non valide.", "invalid_credentials");
        }

        var json = await ReadJsonAsync(response, ct);
        return json.RootElement.TryGetProperty("sessionToken", out var t) ? t.GetString() ?? string.Empty : string.Empty;
    }

    private async Task<string> CreateCallbackAsync(string authRequestId, string sessionId, string sessionToken, CancellationToken ct)
    {
        var body = new { session = new { sessionId, sessionToken } };
        var response = await SendAsync(HttpMethod.Post, $"v2/oidc/auth_requests/{Uri.EscapeDataString(authRequestId)}", body, ct);

        if (!response.IsSuccessStatusCode)
        {
            // Password checked out, but Zitadel still won't finalize the auth request — the most
            // likely reason is the account's login policy requires a factor beyond password
            // (MFA/passkey) that this native flow doesn't submit. The caller falls back to the
            // browser flow, which can satisfy any factor Zitadel's hosted UI supports.
            _logger.LogInformation("Zitadel CreateCallback rejected {Status} after a valid password check", response.StatusCode);
            throw new DomainRuleException("Verifica aggiuntiva richiesta.", "additional_factor_required");
        }

        var json = await ReadJsonAsync(response, ct);
        var callbackUrl = json.RootElement.GetProperty("callbackUrl").GetString()
            ?? throw new ServiceUnavailableException("Accesso non disponibile al momento.", "identity_provider_unavailable");

        var code = ExtractCodeFromCallbackUrl(callbackUrl);
        return code ?? throw new ServiceUnavailableException("Accesso non disponibile al momento.", "identity_provider_unavailable");
    }

    /// <summary>
    /// Pulls `code` out of the callback URL's query string by hand — no dependency on
    /// Microsoft.AspNetCore.WebUtilities, which this project (a plain class library, not an
    /// ASP.NET Core web SDK project) does not already reference.
    /// </summary>
    internal static string? ExtractCodeFromCallbackUrl(string callbackUrl)
    {
        var query = new Uri(callbackUrl).Query;
        if (query.Length == 0) return null;

        foreach (var pair in query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = pair.Split('=', 2);
            if (parts.Length == 2 && parts[0] == "code")
                return Uri.UnescapeDataString(parts[1]);
        }
        return null;
    }

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, object body, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(body, _json);
        var request = new HttpRequestMessage(method, path)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.LoginClientPersonalAccessToken);

        try
        {
            return await _http.SendAsync(request, ct);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Zitadel {Method} {Path} unreachable", method, path);
            throw new ServiceUnavailableException("Accesso non disponibile al momento.", "identity_provider_unavailable");
        }
    }

    private static async Task<JsonDocument> ReadJsonAsync(HttpResponseMessage response, CancellationToken ct) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
}
```

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `dotnet test --filter ZitadelSessionServiceTests`
Expected: PASS, all 5 tests.

- [ ] **Step 6: Reconcile against Task 1's real verification output.** If the actual `POST /v2/sessions` response shape recorded in Task 1 differs from `{sessionId, sessionToken}` (field names/casing), update `CreateSessionAsync` and its test now, before moving on.

- [ ] **Step 7: Commit.**

```bash
git add src/TaskTapAPI.Application/Services/Identity/IZitadelSessionService.cs \
        src/TaskTapAPI.Application/Services/Identity/ZitadelSessionService.cs \
        tests/TaskTapAPI.Tests/Services/ZitadelSessionServiceTests.cs
git commit -m "Add ZitadelSessionService for native password login"
```

---

## Task 4: Backend — wire up `POST api/MobileAuth/login`

**Files:**
- Modify: `src/TaskTapAPI.Api/Controllers/MobileAuthController.cs`
- Modify: `src/TaskTapAPI.Api/Program.cs`
- Test: `tests/TaskTapAPI.Tests/Controllers/MobileAuthControllerTests.cs` (create; check for an existing controller test file first to match its HTTP-test-host conventions, e.g. `AppRapportiniTests.cs` or similar `WebApplicationFactory`-based test)

**Interfaces:**
- Consumes: `IZitadelSessionService.LoginAsync` (Task 3).
- Produces: `POST api/MobileAuth/login` — request `{ authRequestId, loginName, password }` → `200 { code }` or a `problem+json` error with `code` = `invalid_credentials` | `additional_factor_required` | `identity_provider_unavailable` — consumed by Task 8 (mobile).

- [ ] **Step 1: Check how another anonymous-but-live controller is tested in this repo.**

Run: `find tests/TaskTapAPI.Tests/Controllers -iname "*.cs" | head -5` and read one that hits a real HTTP pipeline (not just calls a service directly) to match its `WebApplicationFactory`/DI-override style. Use that exact pattern for this task's test — do not invent a different one.

- [ ] **Step 2: Write the failing test**, following the pattern found in Step 1, structured as these four cases (adapt the exact harness calls to match what Step 1 found):

```csharp
// Pseudocode shape — replace the harness setup/assertion calls with this repo's own
// WebApplicationFactory pattern found in Step 1. The four cases to cover:

// 1. Happy path: IZitadelSessionService.LoginAsync returns "abc123" →
//    POST api/MobileAuth/login {authRequestId, loginName, password} → 200 {"code":"abc123"}

// 2. IZitadelSessionService.LoginAsync throws DomainRuleException(code: "invalid_credentials") →
//    400 problem+json with "code":"invalid_credentials"

// 3. IZitadelSessionService.LoginAsync throws DomainRuleException(code: "additional_factor_required") →
//    400 problem+json with "code":"additional_factor_required"

// 4. IZitadelSessionService.LoginAsync throws ServiceUnavailableException(code: "identity_provider_unavailable") →
//    503 problem+json with "code":"identity_provider_unavailable"
```

Register a fake `IZitadelSessionService` (throwing or returning per case) via the test factory's service override, matching how the file found in Step 1 overrides its own dependencies.

- [ ] **Step 3: Run the tests to verify they fail.**

Run: `dotnet test --filter MobileAuthControllerTests`
Expected: FAIL — the endpoint still returns 410.

- [ ] **Step 4: Update the controller.**

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TaskTapAPI.Application.Services.Identity;

namespace TaskTapAPI.Api.Controllers;

public class LoginRequest
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

/// <summary>Request body for the native-password login flow (see IZitadelSessionService).</summary>
public class NativeLoginRequest
{
    public string AuthRequestId { get; set; } = string.Empty;
    public string LoginName { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

public class RefreshRequest
{
    public string RefreshToken { get; set; } = string.Empty;
}

/// <summary>
/// Mobile auth. <see cref="Login"/> proxies Zitadel's Session API for native
/// (in-app) password login — see IZitadelSessionService's own doc comment for why this can't be
/// called directly from the mobile client. Refresh/register stay OIDC-client-side, retired here.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[AllowAnonymous]
public class MobileAuthController : ControllerBase
{
    private readonly IZitadelSessionService _sessions;

    public MobileAuthController(IZitadelSessionService sessions) => _sessions = sessions;

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] NativeLoginRequest request, CancellationToken ct)
    {
        var code = await _sessions.LoginAsync(request.AuthRequestId, request.LoginName, request.Password, ct);
        return Ok(new { code });
    }

    [HttpPost("refresh")]
    public IActionResult Refresh() =>
        StatusCode(410, new { error = "Use the OIDC client for token refresh. This endpoint is retired." });

    [HttpPost("register")]
    public IActionResult Register() =>
        StatusCode(410, new { error = "Use POST /api/auth/register. This endpoint is retired." });
}
```

Note: `DomainRuleException`/`ServiceUnavailableException` thrown by `_sessions.LoginAsync` are caught by the existing global `ErrorHandlingMiddleware` — the controller does not need its own try/catch.

- [ ] **Step 5: Register the new service in `Program.cs`**, immediately after the existing `IIdentityAdminService` registration (around line 222):

```csharp
builder.Services.AddHttpClient<IZitadelSessionService, ZitadelSessionService>()
    .AddHttpMessageHandler<ZitadelForwardingHandler>()
    .AddResiliencePolicies("ZitadelSession");
```

- [ ] **Step 6: Run the tests to verify they pass.**

Run: `dotnet test --filter MobileAuthControllerTests`
Expected: PASS, all 4 cases.

- [ ] **Step 7: Run the full backend test suite to check for regressions.**

Run: `dotnet test`
Expected: same pass/fail count as before this task, plus the new tests passing.

- [ ] **Step 8: Commit.**

```bash
git add src/TaskTapAPI.Api/Controllers/MobileAuthController.cs src/TaskTapAPI.Api/Program.cs \
        tests/TaskTapAPI.Tests/Controllers/MobileAuthControllerTests.cs
git commit -m "Wire POST api/MobileAuth/login to ZitadelSessionService"
```

- [ ] **Step 9: Push the worktree branch and open a PR (or note the branch name) for review — do not merge to `master` without the user's explicit go-ahead, per this project's standing rule on backend branches.**

---

## Task 5: Mobile — PKCE helper

**Files:**
- Create: `lib/data/auth/pkce.dart`
- Test: `test/data/auth/pkce_test.dart`

**Interfaces:**
- Produces: `Pkce.generate()` → `({String verifier, String challenge})` — consumed by Task 7.

- [ ] **Step 1: Add the `crypto` package.**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
flutter pub add crypto
```

- [ ] **Step 2: Write the failing test.**

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/auth/pkce.dart';

void main() {
  group('Pkce.generate', () {
    test('challenge is the base64url(no padding) SHA-256 of the verifier', () {
      final pair = Pkce.generate();

      final expected = base64Url
          .encode(sha256.convert(utf8.encode(pair.verifier)).bytes)
          .replaceAll('=', '');
      expect(pair.challenge, expected);
    });

    test('verifier is 43-128 chars of the unreserved character set (RFC 7636)', () {
      final pair = Pkce.generate();
      expect(pair.verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(pair.verifier), isTrue);
    });

    test('two calls produce different verifiers', () {
      final a = Pkce.generate();
      final b = Pkce.generate();
      expect(a.verifier, isNot(equals(b.verifier)));
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails.**

Run (from the WSL-native scratch copy — copy `pkce.dart`'s test-and-source pair there first, per this project's own testing convention): `fvm dart test test/data/auth/pkce_test.dart`
Expected: FAIL — `Pkce` doesn't exist yet.

- [ ] **Step 4: Write the implementation.**

```dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PKCE (RFC 7636) verifier/challenge pair for a single authorization request.
///
/// Generated locally rather than via `flutter_appauth` — that package's own API only knows how
/// to drive a full browser-based authorize+token round trip, and the native-login flow needs the
/// verifier before it opens anything (see `ZitadelAuthRepository.signInWithPassword`).
class Pkce {
  const Pkce._({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;

  static const _unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static ({String verifier, String challenge}) generate() {
    final random = Random.secure();
    // 96 chars — comfortably inside RFC 7636's 43-128 char verifier range.
    final verifier = List.generate(96, (_) => _unreserved[random.nextInt(_unreserved.length)]).join();
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    return (verifier: verifier, challenge: challenge);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `fvm dart test test/data/auth/pkce_test.dart`
Expected: PASS, all 3 tests.

- [ ] **Step 6: Copy both files back to the real repo checkout and commit.**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
git add lib/data/auth/pkce.dart test/data/auth/pkce_test.dart pubspec.yaml pubspec.lock
git commit -m "Add local PKCE verifier/challenge generator"
```

---

## Task 6: Mobile — `AuthFailure.AdditionalFactorRequired`

**Files:**
- Modify: `lib/domain/auth/auth_failure.dart`
- Modify: `test/data/auth/auth_failure_test.dart`

**Interfaces:**
- Produces: `AdditionalFactorRequired` (new `AuthFailure` subtype) — consumed by Task 8.

- [ ] **Step 1: Write the failing test** (add to the existing `authFailureMessage — Italian error strings` group in `test/data/auth/auth_failure_test.dart`):

```dart
test('AdditionalFactorRequired returns a verification-needed message', () {
  expect(
    authFailureMessage(const AdditionalFactorRequired()),
    'Serve una verifica aggiuntiva. Accedi dal browser per continuare.',
  );
});
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `fvm flutter test test/data/auth/auth_failure_test.dart`
Expected: FAIL — `AdditionalFactorRequired` doesn't exist.

- [ ] **Step 3: Add the type and its message.**

In `lib/domain/auth/auth_failure.dart`, add after `InvalidCredentials`:

```dart
/// The account needs a verification factor beyond password (MFA, passkey) that the native
/// login form doesn't support yet — see `ZitadelAuthRepository.signInWithPassword`'s own doc
/// comment. Callers fall back to the browser flow automatically; this type exists mainly so the
/// fallback has something typed to switch on, not because it's normally shown as an error.
class AdditionalFactorRequired extends AuthFailure {
  const AdditionalFactorRequired();
}
```

And add a case to `authFailureMessage`'s `switch`:

```dart
AdditionalFactorRequired() => 'Serve una verifica aggiuntiva. Accedi dal browser per continuare.',
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `fvm flutter test test/data/auth/auth_failure_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add lib/domain/auth/auth_failure.dart test/data/auth/auth_failure_test.dart
git commit -m "Add AdditionalFactorRequired auth failure"
```

---

## Task 7: Mobile — `IAuthRepository.signInWithPassword` (interface)

**Files:**
- Modify: `lib/domain/auth/i_auth_repository.dart`

**Interfaces:**
- Produces: `IAuthRepository.signInWithPassword(String loginName, String password)` → `Future<({AuthUser? user, AuthFailure? failure})>` — same result shape as the existing `signIn()`, consumed by Task 9.

- [ ] **Step 1: Add the method to the interface.**

```dart
/// Native in-app password sign-in — submits credentials directly instead of opening the
/// system browser. See `ZitadelAuthRepository.signInWithPassword`'s own doc comment for the
/// full flow and its fallback triggers.
///
/// Returns the signed-in [AuthUser] on success. On failure, [AuthFailure] is
/// [AdditionalFactorRequired] when the caller should fall back to [signIn] (the account needs
/// more than a password), or any other [AuthFailure] when it should not (wrong credentials,
/// network error, unexpected upstream error).
Future<({AuthUser? user, AuthFailure? failure})> signInWithPassword(String loginName, String password);
```

Add this to `i_auth_repository.dart` after the existing `signIn()` method. No test for this step alone — it's an interface addition; `ZitadelAuthRepository` (Task 8) not yet implementing it will fail to compile, which Task 8 resolves.

- [ ] **Step 2: Commit.**

```bash
git add lib/domain/auth/i_auth_repository.dart
git commit -m "Add signInWithPassword to IAuthRepository"
```

---

## Task 8: Mobile — `ZitadelAuthRepository.signInWithPassword` (implementation)

**Files:**
- Modify: `lib/data/auth/zitadel_auth_repository.dart`
- Modify: `test/data/auth/zitadel_auth_repository_test.dart`

**Interfaces:**
- Consumes: `Pkce.generate()` (Task 5), `AdditionalFactorRequired` (Task 6), `Env.apiBaseUrl`/`Env.oidcIssuer`/`Env.oidcClientId`/`Env.oidcRedirectUri` (existing).
- Produces: `ZitadelAuthRepository.signInWithPassword` fulfilling Task 7's interface — consumed by Task 9.

- [ ] **Step 1: Write the failing tests.** Add a new group to `test/data/auth/zitadel_auth_repository_test.dart`, following the existing revocation tests' pattern of injecting a `MockDio` (already defined at the top of this file) as `revocationHttpClient` — this same field is reused for the new BFF calls, not a new constructor parameter (see Step 3's doc-comment update).

```dart
group('signInWithPassword', () {
  late MockDio httpClient;

  setUp(() {
    httpClient = MockDio();
    registerFallbackValue(Options());
  });

  /// Stubs the GET /oauth/v2/authorize redirect-capture call to return a 302 with the given
  /// authRequestId in its Location header — the shape every case in this group starts from.
  void stubAuthorizeRedirect(String authRequestId) {
    when(
      () => httpClient.get<void>(
        any(that: contains('/oauth/v2/authorize')),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: '/oauth/v2/authorize'),
        statusCode: 302,
        headers: Headers.fromMap({
          'location': ['https://issuer.test/ui/v1/login?authRequestId=$authRequestId'],
        }),
      ),
    );
  }

  test('happy path: authorize redirect + backend login + token exchange', () async {
    stubAuthorizeRedirect('authreq-1');
    when(
      () => httpClient.post<dynamic>(
        any(that: contains('/api/MobileAuth/login')),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
        statusCode: 200,
        data: {'code': 'abc123'},
      ),
    );
    when(() => appAuth.token(any())).thenAnswer(
      // Positional order per flutter_appauth_platform_interface's TokenResponse: accessToken,
      // refreshToken, accessTokenExpirationDateTime, idToken, tokenType, scopes,
      // tokenAdditionalParameters — 7 params, all but the first four left null here.
      (_) async => TokenResponse(
        'access-1', 'refresh-1', DateTime.now().add(const Duration(hours: 1)),
        _fakeIdToken(), null, null, null,
      ),
    );

    final repo = ZitadelAuthRepository(
      appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
    );

    final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

    expect(result.failure, isNull);
    expect(result.user?.accessToken, 'access-1');

    final tokenCall = verify(() => appAuth.token(captureAny())).captured.single as TokenRequest;
    expect(tokenCall.authorizationCode, 'abc123');
    expect(tokenCall.codeVerifier, isNotEmpty);
  });

  test('wrong credentials: backend returns invalid_credentials, no fallback', () async {
    stubAuthorizeRedirect('authreq-1');
    when(
      () => httpClient.post<dynamic>(
        any(that: contains('/api/MobileAuth/login')),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
          statusCode: 400,
          data: {'code': 'invalid_credentials'},
        ),
      ),
    );

    final repo = ZitadelAuthRepository(
      appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
    );

    final result = await repo.signInWithPassword('tech@tasktap.io', 'wrong-password');

    expect(result.user, isNull);
    expect(result.failure, isA<InvalidCredentials>());
    verifyNever(() => appAuth.token(any()));
  });

  test('additional factor required: typed as AdditionalFactorRequired', () async {
    stubAuthorizeRedirect('authreq-1');
    when(
      () => httpClient.post<dynamic>(
        any(that: contains('/api/MobileAuth/login')),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/MobileAuth/login'),
          statusCode: 400,
          data: {'code': 'additional_factor_required'},
        ),
      ),
    );

    final repo = ZitadelAuthRepository(
      appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
    );

    final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

    expect(result.user, isNull);
    expect(result.failure, isA<AdditionalFactorRequired>());
  });

  test('network error surfaces as NetworkError', () async {
    when(
      () => httpClient.get<void>(
        any(that: contains('/oauth/v2/authorize')),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/oauth/v2/authorize'),
        type: DioExceptionType.connectionError,
      ),
    );

    final repo = ZitadelAuthRepository(
      appAuth: appAuth, storage: storage, revocationHttpClient: httpClient, restore: false,
    );

    final result = await repo.signInWithPassword('tech@tasktap.io', 'correct-password');

    expect(result.user, isNull);
    expect(result.failure, isA<NetworkError>());
  });
});
```

Add `registerFallbackValue(RequestOptions(path: ''));` alongside the existing `setUpAll` fallback registrations if `any(named: 'options')` needs it (check the test run in the next step — Mocktail will name the missing fallback type in its failure message if so).

- [ ] **Step 2: Run the tests to verify they fail.**

Run (from the WSL-native scratch copy): `fvm flutter test test/data/auth/zitadel_auth_repository_test.dart`
Expected: FAIL — `signInWithPassword` doesn't exist yet.

- [ ] **Step 3: Implement `signInWithPassword`.** Add to `ZitadelAuthRepository`, and update the class's own doc comment and the `_revocationHttpClient` field's doc comment (it now serves two purposes):

```dart
  /// Plain HTTP client for calls that must not go through `dioProvider`'s `AuthInterceptor` —
  /// revoking the refresh token at sign-out (see [_revokeRefreshToken]), and the native-login
  /// BFF calls below ([signInWithPassword]). Revocation needs no bearer token; a login attempt
  /// has none yet to attach — either way, `AuthInterceptor`'s 401-retry-then-forced-signout logic
  /// is the wrong behavior for both, since neither is an authenticated-session request.
  final Dio _revocationHttpClient;
```

```dart
  @override
  Future<({AuthUser? user, AuthFailure? failure})> signInWithPassword(
    String loginName,
    String password,
  ) async {
    final pkce = Pkce.generate();

    final String authRequestId;
    try {
      authRequestId = await _captureAuthRequestId(pkce.challenge);
    } catch (e) {
      return (user: null, failure: _mapError(e));
    }

    final String code;
    try {
      final response = await _revocationHttpClient.post<dynamic>(
        '${Env.apiBaseUrl}/api/MobileAuth/login',
        data: {'authRequestId': authRequestId, 'loginName': loginName, 'password': password},
        options: Options(contentType: Headers.jsonContentType),
      );
      code = response.data['code'] as String;
    } on DioException catch (e) {
      final backendCode = e.response?.data is Map ? e.response?.data['code'] as String? : null;
      return (user: null, failure: switch (backendCode) {
        'additional_factor_required' => const AdditionalFactorRequired(),
        'invalid_credentials' => const InvalidCredentials(),
        _ => _mapError(e),
      });
    }

    try {
      final result = await _appAuth.token(
        TokenRequest(
          Env.oidcClientId,
          Env.oidcRedirectUri,
          issuer: Env.oidcIssuer,
          authorizationCode: code,
          codeVerifier: pkce.verifier,
        ),
      );
      final user = _fromTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      if (user == null) {
        return (user: null, failure: const UnknownAuthError('No tokens returned'));
      }
      await _persistRefreshToken(result.refreshToken);
      await _persistCachedIdentity(user);
      _emit(user);
      return (user: user, failure: null);
    } catch (e) {
      return (user: null, failure: _mapError(e));
    }
  }

  /// GETs the OAuth authorize endpoint with redirects disabled and reads `authRequestId` off the
  /// resulting 302's Location header — the same redirect [_appAuth]'s own `authorize()` would
  /// otherwise open a full browser to render. Never rendered here; only the header is read.
  Future<String> _captureAuthRequestId(String codeChallenge) async {
    final uri = Uri.parse('${Env.oidcIssuer}/oauth/v2/authorize').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': Env.oidcClientId,
        'redirect_uri': Env.oidcRedirectUri,
        'scope': _scopes.join(' '),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );

    final response = await _revocationHttpClient.get<void>(
      uri.toString(),
      options: Options(followRedirects: false, validateStatus: (status) => status != null && status < 400),
    );

    final location = response.headers.value('location');
    if (location == null) {
      throw const UnknownAuthError('No redirect from authorize endpoint');
    }
    final authRequestId = Uri.parse(location).queryParameters['authRequestId'];
    if (authRequestId == null || authRequestId.isEmpty) {
      throw const UnknownAuthError('No authRequestId in authorize redirect');
    }
    return authRequestId;
  }
```

Add the import: `import 'pkce.dart';` and `import '../../domain/auth/auth_failure.dart' show AdditionalFactorRequired, InvalidCredentials;` (the file already imports `auth_failure.dart` for `AuthFailure`/`UnknownAuthError`/etc — just confirm the new types are reachable, no duplicate import needed if it's already a bare `import '../../domain/auth/auth_failure.dart';`).

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `fvm flutter test test/data/auth/zitadel_auth_repository_test.dart`
Expected: PASS, all 4 new tests plus every pre-existing test in this file still green.

- [ ] **Step 5: Run `dart analyze` on the touched files.**

Run: `fvm dart analyze lib/data/auth/zitadel_auth_repository.dart lib/data/auth/pkce.dart test/data/auth/zitadel_auth_repository_test.dart`
Expected: No issues found.

- [ ] **Step 6: Copy files back to the real checkout and commit.**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
git add lib/data/auth/zitadel_auth_repository.dart test/data/auth/zitadel_auth_repository_test.dart
git commit -m "Implement ZitadelAuthRepository.signInWithPassword"
```

---

## Task 9: Mobile — `LoginNotifier.signInWithPassword`

**Files:**
- Modify: `lib/presentation/providers/auth_providers.dart`
- Test: `test/presentation/providers/auth_providers_test.dart` (create if it doesn't exist — check first)

**Interfaces:**
- Consumes: `IAuthRepository.signInWithPassword` (Task 8), `IAuthRepository.signIn` (existing).
- Produces: `LoginNotifier.signInWithPassword(String loginName, String password)` — consumed by Task 10 (the new login screen).

- [ ] **Step 1: Check for an existing test file.**

Run: `find test -iname "auth_providers_test.dart"`. If found, read it and follow its mocking style (likely a fake `IAuthRepository`) for the next step instead of the sketch below.

- [ ] **Step 2: Write the failing test.**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/auth/pkce.dart'; // not used directly; keeps imports honest if referenced
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository repo;
  late LoginNotifier notifier;

  setUp(() {
    repo = MockAuthRepository();
    notifier = LoginNotifier(repo);
  });

  group('LoginNotifier.signInWithPassword', () {
    test('success clears loading and failure state', () async {
      final user = AuthUser(
        id: 'u1', email: 'tech@tasktap.io', accessToken: 'a', refreshToken: 'r',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      when(() => repo.signInWithPassword('tech@tasktap.io', 'correct'))
          .thenAnswer((_) async => (user: user, failure: null));

      await notifier.signInWithPassword('tech@tasktap.io', 'correct');

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.failure, isNull);
    });

    test('wrong credentials surfaces InvalidCredentials, does not call signIn', () async {
      when(() => repo.signInWithPassword('tech@tasktap.io', 'wrong')).thenAnswer(
        (_) async => (user: null, failure: const InvalidCredentials()),
      );

      await notifier.signInWithPassword('tech@tasktap.io', 'wrong');

      expect(notifier.state.failure, isA<InvalidCredentials>());
      verifyNever(() => repo.signIn());
    });

    test('AdditionalFactorRequired falls back to signIn() automatically', () async {
      when(() => repo.signInWithPassword('tech@tasktap.io', 'correct')).thenAnswer(
        (_) async => (user: null, failure: const AdditionalFactorRequired()),
      );
      when(() => repo.signIn()).thenAnswer((_) async => (user: null, failure: null));

      await notifier.signInWithPassword('tech@tasktap.io', 'correct');

      verify(() => repo.signIn()).called(1);
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail.**

Run: `fvm flutter test test/presentation/providers/auth_providers_test.dart`
Expected: FAIL — `signInWithPassword` doesn't exist on `LoginNotifier`.

- [ ] **Step 4: Add the method to `LoginNotifier`** in `lib/presentation/providers/auth_providers.dart`, after the existing `signIn()`:

```dart
  Future<void> signInWithPassword(String loginName, String password) async {
    state = const LoginState(isLoading: true);
    final result = await _repo.signInWithPassword(loginName, password);

    if (result.failure is AdditionalFactorRequired) {
      // The account needs more than a password — fall back to the browser flow, which can
      // satisfy MFA/passkey/whatever Zitadel's hosted UI supports. No error shown; this is a
      // transition, not a failure the technician needs to see or act on.
      await signIn();
      return;
    }

    if (result.failure != null) {
      state = LoginState(failure: result.failure);
    } else {
      state = const LoginState();
    }
  }
```

Add the import `import '../../domain/auth/auth_failure.dart';` if not already present (the file already imports it for `AuthFailure` itself — just confirm `AdditionalFactorRequired` is reachable from that same import).

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `fvm flutter test test/presentation/providers/auth_providers_test.dart`
Expected: PASS, all 3 tests.

- [ ] **Step 6: Commit.**

```bash
git add lib/presentation/providers/auth_providers.dart test/presentation/providers/auth_providers_test.dart
git commit -m "Add LoginNotifier.signInWithPassword with MFA-required fallback"
```

---

## Task 10: Mobile — native login screen

**Files:**
- Modify: `lib/presentation/screens/login/login_screen.dart`
- Test: `test/presentation/screens/login/login_screen_test.dart` (create if it doesn't exist — check first)

**Interfaces:**
- Consumes: `LoginNotifier.signInWithPassword` (Task 9), `LoginNotifier.signIn` (existing, used by the "Password dimenticata?" link).

- [ ] **Step 1: Check for an existing test file and mirror its `ProviderScope`/pump helper style.**

Run: `find test -iname "login_screen_test.dart"`. If found, read it fully and reuse its setup rather than the sketch below.

- [ ] **Step 2: Write the failing tests.**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/screens/login/login_screen.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository repo;

  setUp(() {
    repo = MockAuthRepository();
    when(() => repo.currentUser).thenReturn(null);
    when(() => repo.authStateChanges).thenAnswer((_) => const Stream.empty());
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('submitting valid credentials calls signInWithPassword', (tester) async {
    when(() => repo.signInWithPassword(any(), any()))
        .thenAnswer((_) async => (user: null, failure: null));
    await pump(tester);

    await tester.enterText(find.byKey(const ValueKey('login-username')), 'tech@tasktap.io');
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'correct-password');
    await tester.tap(find.text('Accedi'));
    await tester.pump();

    verify(() => repo.signInWithPassword('tech@tasktap.io', 'correct-password')).called(1);
  });

  testWidgets('wrong credentials shows the error banner', (tester) async {
    when(() => repo.signInWithPassword(any(), any())).thenAnswer(
      (_) async => (user: null, failure: const InvalidCredentials()),
    );
    await pump(tester);

    await tester.enterText(find.byKey(const ValueKey('login-username')), 'tech@tasktap.io');
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'wrong');
    await tester.tap(find.text('Accedi'));
    await tester.pumpAndSettle();

    expect(find.text('Email o password errati. Controlla le credenziali e riprova.'), findsOneWidget);
  });

  testWidgets('"Password dimenticata?" calls signIn (browser flow), not signInWithPassword', (tester) async {
    when(() => repo.signIn()).thenAnswer((_) async => (user: null, failure: null));
    await pump(tester);

    await tester.tap(find.text('Password dimenticata?'));
    await tester.pump();

    verify(() => repo.signIn()).called(1);
    verifyNever(() => repo.signInWithPassword(any(), any()));
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail.**

Run: `fvm flutter test test/presentation/screens/login/login_screen_test.dart`
Expected: FAIL — no username/password fields exist yet.

- [ ] **Step 4: Rewrite `LoginScreen`'s body.** Replace the single-button form (from `Text('Accedi', ...)` heading through the `VetroButton` CTA) with:

```dart
class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    ref.read(loginProvider.notifier).clearError();
    await ref.read(loginProvider.notifier).signInWithPassword(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text,
    );
    // Router redirect handles navigation on success.
  }

  Future<void> _onForgotPassword() async {
    ref.read(loginProvider.notifier).clearError();
    // Zitadel's own hosted page has its own password-reset link — no need to build one here.
    await ref.read(loginProvider.notifier).signIn();
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginProvider);
    final isLoading = loginState.isLoading;
    final failure = loginState.failure;

    return Scaffold(
      backgroundColor: context.colors.bg1,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxxl),
              const _TaskTapLogo(),
              const SizedBox(height: AppSpacing.xxxl),
              Text('Accedi', style: AppTextStyles.headlineLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Inserisci le tue credenziali TaskTap.',
                style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (failure != null) ...[
                _ErrorBanner(message: authFailureMessage(failure)),
                const SizedBox(height: AppSpacing.base),
              ],
              AppTextField(
                key: const ValueKey('login-username'),
                controller: _usernameCtrl,
                label: 'Email o nome utente',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.base),
              AppTextField(
                key: const ValueKey('login-password'),
                controller: _passwordCtrl,
                label: 'Password',
                obscureText: true,
                textInputAction: TextInputAction.done,
                onEditingComplete: isLoading ? null : _onLogin,
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isLoading ? null : _onForgotPassword,
                  child: const Text('Password dimenticata?'),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              VetroButton(
                label: 'Accedi',
                onPressed: isLoading ? null : _onLogin,
                isLoading: isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Add the import `import '../../../core/widgets/app_text_field.dart';` (check the exact relative path against this file's existing imports — it already imports sibling `core/widgets/` files the same way for `VetroButton`).

Leave `_TaskTapLogo` and `_ErrorBanner` untouched.

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `fvm flutter test test/presentation/screens/login/login_screen_test.dart`
Expected: PASS, all 3 tests.

- [ ] **Step 6: Run `dart analyze` on the touched file.**

Run: `fvm dart analyze lib/presentation/screens/login/login_screen.dart test/presentation/screens/login/login_screen_test.dart`
Expected: No issues found.

- [ ] **Step 7: Run the full mobile test suite to check for regressions.**

Run: `fvm flutter test`
Expected: same baseline pass count as before this task (see this project's own note on pre-existing contract-drift failures — those are unrelated and expected), plus every new test from Tasks 5-10 passing.

- [ ] **Step 8: Commit.**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
git add lib/presentation/screens/login/login_screen.dart test/presentation/screens/login/login_screen_test.dart
git commit -m "Replace browser-only login screen with native password form"
```

- [ ] **Step 9: Push.**

```bash
git push origin develop
```

---

## Self-Review Notes

- **Spec coverage:** §4 data flow → Tasks 5, 8. §5 components (backend endpoint, `signInWithPassword`, login screen) → Tasks 3-4, 7-8, 10. §6 error handling table → Task 8 (all four outcomes tested) + Task 9 (fallback trigger) + Task 10 (forgot-password trigger). §7 testing → every task's own test step; no live-Zitadel E2E anywhere in this plan, matching the spec's explicit non-goal.
- **Manual prerequisite:** Task 1 cannot be executed by an agent. If using subagent-driven-development, confirm Task 1 is actually done (the PAT exists in config) before dispatching Task 2 — don't let a subagent discover this gap mid-task.
- **Known unverified detail:** `ZitadelSessionService`'s exact JSON field names for `CreateSession`/`SetSession` responses are inferred from Zitadel's public docs and proto source, not from a live call this plan's author could make. Task 1's verification step and Task 3's Step 6 exist specifically to catch and correct any mismatch before it reaches Task 4.
