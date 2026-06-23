/// API error representation.
class ApiError implements Exception {
  const ApiError({required this.message, this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  /// Create ApiError from HTTP status code.
  factory ApiError.fromStatusCode(int statusCode, [String? message]) {
    return ApiError(
      message: message ?? defaultMessageForStatus(statusCode),
      statusCode: statusCode,
    );
  }

  /// Get default error message for HTTP status code.
  static String defaultMessageForStatus(int statusCode) {
    return switch (statusCode) {
      400 => 'Bad request',
      401 => 'Please sign in to continue',
      403 => 'You don\'t have permission to access this',
      404 => 'Not found',
      409 => 'Conflict with existing data',
      422 => 'Invalid data provided',
      429 => 'Too many requests. Please try again later',
      500 => 'Server error. Please try again',
      502 => 'Service temporarily unavailable',
      503 => 'Service temporarily unavailable',
      504 => 'Request timed out',
      _ => 'Something went wrong',
    };
  }

  /// Check if error is authentication related.
  bool get isAuthError => statusCode == 401;

  /// Check if error is permission related.
  bool get isPermissionError => statusCode == 403;

  /// Check if error is not found.
  bool get isNotFoundError => statusCode == 404;

  /// Check if error is validation related.
  bool get isValidationError => statusCode == 422;

  /// Check if error is server error.
  bool get isServerError => statusCode != null && statusCode! >= 500;

  /// Check if error is client error.
  bool get isClientError =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  @override
  String toString() => message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApiError &&
        other.message == message &&
        other.code == code &&
        other.statusCode == statusCode;
  }

  @override
  int get hashCode => Object.hash(message, code, statusCode);
}

/// Network connectivity error.
class NetworkError implements Exception {
  const NetworkError([this.message = 'No internet connection']);

  final String message;

  @override
  String toString() => message;
}

/// Request timeout error.
class TimeoutError implements Exception {
  const TimeoutError([this.message = 'Request timed out. Please try again']);

  final String message;

  @override
  String toString() => message;
}

/// Extension to check error types.
extension ExceptionExtension on Exception {
  /// Check if this is a network error.
  bool get isNetworkError => this is NetworkError;

  /// Check if this is a timeout error.
  bool get isTimeoutError => this is TimeoutError;

  /// Check if this is an API error.
  bool get isApiError => this is ApiError;

  /// Get user-friendly error message.
  String get userMessage {
    if (this is ApiError) return (this as ApiError).message;
    if (this is NetworkError) return (this as NetworkError).message;
    if (this is TimeoutError) return (this as TimeoutError).message;
    return 'Something went wrong';
  }
}
