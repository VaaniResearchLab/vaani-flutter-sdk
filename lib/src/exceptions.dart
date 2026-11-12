/// Typed errors raised by the Vaani SDK. Mirrors the Python `vaani-sdk`.
library;

/// Base class for every error thrown by this SDK.
class VaaniException implements Exception {
  /// Creates a generic Vaani error.
  const VaaniException(this.message, {this.statusCode});

  /// Human-readable message (usually the API's `detail` field).
  final String message;

  /// HTTP status code, when the error came from an HTTP response.
  final int? statusCode;

  @override
  String toString() =>
      '$runtimeType(message: $message${statusCode == null ? '' : ', statusCode: $statusCode'})';
}

/// 401 — the API key is missing, invalid or revoked.
class VaaniAuthenticationException extends VaaniException {
  /// Creates a 401 error.
  const VaaniAuthenticationException([super.message = 'Invalid or missing API key'])
      : super(statusCode: 401);
}

/// 402 — wallet balance too low.
class VaaniInsufficientBalanceException extends VaaniException {
  /// Creates a 402 error.
  const VaaniInsufficientBalanceException([super.message = 'Insufficient balance'])
      : super(statusCode: 402);
}

/// 403 — the operation is not allowed for this key (e.g. DND block).
class VaaniForbiddenException extends VaaniException {
  /// Creates a 403 error.
  const VaaniForbiddenException([super.message = 'Forbidden']) : super(statusCode: 403);
}

/// 404 — the resource (agent, call, session) does not exist.
class VaaniNotFoundException extends VaaniException {
  /// Creates a 404 error.
  const VaaniNotFoundException([super.message = 'Resource not found']) : super(statusCode: 404);
}

/// 410 — the WebRTC session has ended or expired.
class VaaniSessionExpiredException extends VaaniException {
  /// Creates a 410 error.
  const VaaniSessionExpiredException([super.message = 'Session expired'])
      : super(statusCode: 410);
}

/// 422 — request parameters failed server-side validation.
class VaaniValidationException extends VaaniException {
  /// Creates a 422 error.
  const VaaniValidationException([super.message = 'Validation error']) : super(statusCode: 422);
}

/// 429 — rate limit exceeded.
class VaaniRateLimitException extends VaaniException {
  /// Creates a 429 error.
  const VaaniRateLimitException([super.message = 'Rate limit exceeded']) : super(statusCode: 429);
}

/// 5xx — Vaani server-side error.
class VaaniServerException extends VaaniException {
  /// Creates a 5xx error.
  const VaaniServerException([super.message = 'Internal server error', int statusCode = 500])
      : super(statusCode: statusCode);
}

/// The request did not complete within the configured timeout.
class VaaniTimeoutException extends VaaniException {
  /// Creates a timeout error.
  const VaaniTimeoutException([super.message = 'Request timed out']);
}

/// The SDK could not reach the Vaani API (DNS, TLS, offline, ...).
class VaaniConnectionException extends VaaniException {
  /// Creates a connection error.
  const VaaniConnectionException([super.message = 'Could not connect to Vaani API']);
}

/// Maps an HTTP status code and message to the matching typed exception.
VaaniException vaaniExceptionForStatus(int statusCode, String message) {
  switch (statusCode) {
    case 401:
      return VaaniAuthenticationException(message);
    case 402:
      return VaaniInsufficientBalanceException(message);
    case 403:
      return VaaniForbiddenException(message);
    case 404:
      return VaaniNotFoundException(message);
    case 410:
      return VaaniSessionExpiredException(message);
    case 422:
      return VaaniValidationException(message);
    case 429:
      return VaaniRateLimitException(message);
  }
  if (statusCode >= 500) return VaaniServerException(message, statusCode);
  return VaaniException(message, statusCode: statusCode);
}
