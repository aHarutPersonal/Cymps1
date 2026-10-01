import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env.dart';
import '../storage/token_store.dart';
import 'api_error.dart';
import 'single_flight.dart';

/// Dio instance provider. Shares the [dioClientProvider] instance so the app
/// runs on one Dio with one set of interceptors.
final dioProvider = Provider<Dio>((ref) {
  return ref.watch(dioClientProvider).dio;
});

/// Dio client provider (for direct access to DioClient methods).
final dioClientProvider = Provider<DioClient>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  return DioClient(tokenStore: tokenStore);
});

/// Configured Dio HTTP client with automatic token injection and error handling.
///
/// Features:
/// - Automatic Bearer token injection from TokenStore
/// - Response error mapping to typed ApiError
/// - Request/response logging in debug mode
/// - Timeout configuration
///
/// Usage:
/// ```dart
/// final dio = ref.read(dioProvider);
/// final response = await dio.get('/users/me');
///
/// // Or use DioClient for convenience methods:
/// final client = ref.read(dioClientProvider);
/// final response = await client.get('/users/me');
/// ```
class DioClient {
  DioClient({required TokenStore tokenStore, Dio? refreshDio})
    : _tokenStore = tokenStore,
      _refreshDio = refreshDio {
    _dio = Dio(_createBaseOptions());
    _setupInterceptors();
  }

  final TokenStore _tokenStore;
  final Dio? _refreshDio;
  late final Dio _dio;
  static const _maxErrorBodyBytes = 64 * 1024;

  /// Get the Dio instance.
  Dio get dio => _dio;

  /// Get the base URL.
  String get baseUrl => Env.apiBaseUrl;

  /// Get the auth token for external HTTP requests.
  Future<String?> getAuthToken() async {
    return _tokenStore.readAccessToken();
  }

  /// Create base options with environment URL.
  BaseOptions _createBaseOptions() {
    return BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      // Only treat 2xx responses as valid; everything else throws
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    );
  }

  /// Setup all interceptors.
  void _setupInterceptors() {
    // Auth interceptor - adds Bearer token
    _dio.interceptors.add(_authInterceptor);

    // Error interceptor - maps errors to ApiError
    _dio.interceptors.add(_errorInterceptor);

    // Logging interceptor (debug only)
    if (kDebugMode && Env.enableLogging) {
      _dio.interceptors.add(_loggingInterceptor);
    }
  }

  /// Auth interceptor - automatically adds Authorization header.
  InterceptorsWrapper get _authInterceptor => InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Skip auth for public endpoints
      if (options.extra['skipAuth'] == true) {
        return handler.next(options);
      }

      // Get token from secure storage
      final token = await _tokenStore.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }

      handler.next(options);
    },
  );

  /// Error interceptor - maps DioException to typed errors and handles 401 Refresh.
  ///
  /// At most ONE refresh+retry per original request. Marker `_authRetried` on
  /// the request options breaks the loop where refresh succeeds with a token
  /// that still 401s (e.g. a refresh token from a different backend that the
  /// server happens to accept but the access token it issues is unusable).
  static const _retryMarker = '_authRetried';

  InterceptorsWrapper get _errorInterceptor => InterceptorsWrapper(
    onError: (error, handler) async {
      final alreadyRetried = error.requestOptions.extra[_retryMarker] == true;

      final needsAuth = error.requestOptions.extra['skipAuth'] != true;
      if (needsAuth && error.response?.statusCode == 401 && !alreadyRetried) {
        try {
          if (await _refreshToken()) {
            final options = error.requestOptions;
            options.extra[_retryMarker] = true;
            final newToken = await _tokenStore.readAccessToken();
            options.headers['Authorization'] = 'Bearer $newToken';
            final response = await _dio.fetch(options);
            return handler.resolve(response);
          }
          await _tokenStore.clear();
        } on DioException catch (retryError) {
          // Preserve a valid session on network errors, 429s or 5xxs, and
          // surface the actual failure so the UI offers retry instead of login.
          await _decodeStreamingErrorBody(retryError);
          return handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: retryError.response,
              type: retryError.type,
              error: _mapError(retryError),
            ),
          );
        }
      } else if (needsAuth &&
          error.response?.statusCode == 401 &&
          alreadyRetried) {
        await _tokenStore.clear();
      }

      // `ResponseType.stream` also applies to non-2xx responses, so Dio leaves
      // FastAPI's small JSON error body as a ResponseBody instead of decoding
      // it. Consume only a bounded error body before mapping it; otherwise
      // coded interview conflicts degrade into generic 409s in the UI.
      await _decodeStreamingErrorBody(error);

      handler.reject(
        DioException(
          requestOptions: error.requestOptions,
          response: error.response,
          type: error.type,
          error: _mapError(error),
        ),
      );
    },
  );

  Future<void> _decodeStreamingErrorBody(DioException error) async {
    final response = error.response;
    final body = response?.data;
    if (response == null || body is! ResponseBody) return;

    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > _maxErrorBodyBytes) return;
        bytes.add(chunk);
      }
      response.data = jsonDecode(utf8.decode(bytes.takeBytes()));
    } catch (_) {
      // A malformed/aborted error stream still maps by HTTP status below.
    }
  }

  final SingleFlight<bool> _refreshFlight = SingleFlight<bool>();

  /// Attempt to refresh the access token.
  Future<bool> _refreshToken() => _refreshFlight.run(_performTokenRefresh);

  Future<bool> _performTokenRefresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    final refreshDio = _refreshDio ?? Dio(_createBaseOptions());
    try {
      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data;
      final access = data is Map ? data['accessToken'] : null;
      final refresh = data is Map ? data['refreshToken'] : null;
      if (access is! String ||
          access.isEmpty ||
          refresh is! String ||
          refresh.isEmpty) {
        throw DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.unknown,
          error: const ApiError(
            message: 'Invalid session refresh response. Please retry.',
          ),
        );
      }
      await _tokenStore.saveTokens(
        accessToken: access,
        refreshToken: refresh,
        apiBase: Env.apiBaseUrl,
      );
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) return false;
      rethrow;
    } finally {
      if (_refreshDio == null) refreshDio.close();
    }
  }

  /// Logging interceptor for debug mode.
  static final _loggingInterceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      final hasAuth = options.headers.containsKey('Authorization');
      // ignore: avoid_print
      print('→ ${options.method} ${options.uri} ${hasAuth ? '🔐' : ''}');
      handler.next(options);
    },
    onResponse: (response, handler) {
      // ignore: avoid_print
      print('← ${response.statusCode} ${response.requestOptions.uri}');
      handler.next(response);
    },
    onError: (error, handler) {
      // ignore: avoid_print
      print(
        '✗ ${error.response?.statusCode ?? 'ERR'} ${error.requestOptions.uri}',
      );
      handler.next(error);
    },
  );

  /// Map DioException to typed error.
  Exception _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutError();

      case DioExceptionType.connectionError:
        return const NetworkError();

      case DioExceptionType.badCertificate:
        return const ApiError(message: 'Certificate error');

      case DioExceptionType.badResponse:
        return _mapResponseError(e.response);

      case DioExceptionType.cancel:
        return const ApiError(message: 'Request cancelled');

      case DioExceptionType.unknown:
        if (e.error is ApiError) {
          return e.error as ApiError;
        }
        return ApiError(message: e.message ?? 'Unknown error');
    }
  }

  /// Map response to ApiError.
  ApiError _mapResponseError(Response? response) {
    if (response == null) {
      return const ApiError(message: 'No response from server');
    }

    final statusCode = response.statusCode ?? 500;
    final data = response.data;

    // Try to extract error message from response body
    String? message;
    String? code;

    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is Map) {
        message = detail['message']?.toString();
        code = detail['code']?.toString();
      }
      message ??=
          data['message']?.toString() ??
          data['error']?.toString() ??
          detail?.toString();
      code ??= data['code']?.toString();
    }

    return ApiError(
      message: message ?? ApiError.defaultMessageForStatus(statusCode),
      code: code,
      statusCode: statusCode,
    );
  }

  // ============================================
  // CONVENIENCE REQUEST METHODS
  // ============================================

  /// GET request with error handling.
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    try {
      var mergedOptions = _mergeOptions(options, skipAuth: skipAuth);
      if (receiveTimeout != null) {
        mergedOptions = mergedOptions.copyWith(receiveTimeout: receiveTimeout);
      }
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: mergedOptions,
      );
    } on DioException catch (e) {
      throw e.error ?? _mapError(e);
    }
  }

  /// POST request with error handling.
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, skipAuth: skipAuth),
      );
    } on DioException catch (e) {
      throw e.error ?? _mapError(e);
    }
  }

  /// PUT request with error handling.
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    try {
      return await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, skipAuth: skipAuth),
      );
    } on DioException catch (e) {
      throw e.error ?? _mapError(e);
    }
  }

  /// PATCH request with error handling.
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    try {
      return await _dio.patch<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, skipAuth: skipAuth),
      );
    } on DioException catch (e) {
      throw e.error ?? _mapError(e);
    }
  }

  /// DELETE request with error handling.
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    try {
      return await _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _mergeOptions(options, skipAuth: skipAuth),
      );
    } on DioException catch (e) {
      throw e.error ?? _mapError(e);
    }
  }

  /// Merge options with skipAuth extra.
  Options _mergeOptions(Options? options, {required bool skipAuth}) {
    final extra = <String, dynamic>{
      ...?options?.extra,
      if (skipAuth) 'skipAuth': true,
    };

    if (options == null) {
      return Options(extra: extra);
    }

    return options.copyWith(extra: extra);
  }
}
