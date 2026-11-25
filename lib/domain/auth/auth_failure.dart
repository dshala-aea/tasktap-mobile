/// Typed failure returned by the auth layer instead of raw exceptions.
///
/// Presentation code maps these to friendly Italian UI strings via
/// [authFailureMessage].
sealed class AuthFailure {
  const AuthFailure();
}

/// The user closed the browser sign-in without finishing. Not an error: the screen answers with a
/// calm "try again whenever you like" and nothing is lost.
class SignInCancelled extends AuthFailure {
  const SignInCancelled();
}

/// The identity provider is temporarily unreachable or misbehaving.
class ServiceUnavailable extends AuthFailure {
  const ServiceUnavailable();
}

/// The account has been disabled by an admin.
class AccountDisabled extends AuthFailure {
  const AccountDisabled();
}

/// The email address is not registered.
class EmailNotFound extends AuthFailure {
  const EmailNotFound();
}

/// Too many failed attempts — temporary lockout.
class TooManyRequests extends AuthFailure {
  const TooManyRequests();
}

/// No network connectivity.
class NetworkError extends AuthFailure {
  const NetworkError();
}

/// The refresh token is invalid or expired — user must log in again.
class SessionExpired extends AuthFailure {
  const SessionExpired();
}

/// Any other unexpected error.
class UnknownAuthError extends AuthFailure {
  const UnknownAuthError(this.message);
  final String message;
}

/// Maps an [AuthFailure] to a user-facing Italian string.
String authFailureMessage(AuthFailure failure) => switch (failure) {
  SignInCancelled() =>
      'Accesso annullato. Tocca Accedi quando vuoi riprovare.',
  ServiceUnavailable() =>
    'Servizio temporaneamente non disponibile. Riprova tra poco.',
  AccountDisabled() =>
    'Il tuo account è stato disabilitato. Contatta l\'assistenza.',
  EmailNotFound() => 'Nessun account trovato con questa email.',
  TooManyRequests() =>
    'Troppi tentativi. Attendi qualche minuto prima di riprovare.',
  NetworkError() =>
      'Nessuna connessione. Per accedere serve internet: controlla la rete e riprova.',
  SessionExpired() => 'La sessione è scaduta. Effettua nuovamente l\'accesso.',
  UnknownAuthError(:final message) =>
    'Si è verificato un errore imprevisto. ($message)',
};
