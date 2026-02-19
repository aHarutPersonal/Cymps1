import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_models.freezed.dart';

/// Response from authentication endpoints.
/// Supports both camelCase (accessToken) and snake_case (access_token) from backend.
@freezed
class AuthResponse with _$AuthResponse {
  const factory AuthResponse({
    required String accessToken,
    String? refreshToken,
    @Default('Bearer') String tokenType,
    int? expiresIn,
  }) = _AuthResponse;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    // Handle both camelCase and snake_case from backend
    return AuthResponse(
      accessToken: (json['accessToken'] ?? json['access_token'] ?? '').toString(),
      refreshToken: (json['refreshToken'] ?? json['refresh_token'])?.toString(),
      tokenType: (json['tokenType'] ?? json['token_type'] ?? 'Bearer').toString(),
      expiresIn: (json['expiresIn'] ?? json['expires_in']) as int?,
    );
  }
}

/// Request for login.
@freezed
class LoginRequest with _$LoginRequest {
  const LoginRequest._();
  const factory LoginRequest({
    required String email,
    required String password,
  }) = _LoginRequest;

  factory LoginRequest.fromJson(Map<String, dynamic> json) {
    return LoginRequest(
      email: (json['email'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
  };
}

/// Request for registration.
@freezed
class RegisterRequest with _$RegisterRequest {
  const RegisterRequest._();
  const factory RegisterRequest({
    required String email,
    required String password,
    String? fullName,
  }) = _RegisterRequest;

  factory RegisterRequest.fromJson(Map<String, dynamic> json) {
    return RegisterRequest(
      email: (json['email'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['fullName'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    if (fullName != null) 'full_name': fullName,
  };
}

/// Request for OAuth login.
@freezed
class OAuthRequest with _$OAuthRequest {
  const OAuthRequest._();
  const factory OAuthRequest({
    required String provider,
    required String idToken,
  }) = _OAuthRequest;

  factory OAuthRequest.fromJson(Map<String, dynamic> json) {
    return OAuthRequest(
      provider: (json['provider'] ?? '').toString(),
      idToken: (json['id_token'] ?? json['idToken'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'id_token': idToken,
  };
}
