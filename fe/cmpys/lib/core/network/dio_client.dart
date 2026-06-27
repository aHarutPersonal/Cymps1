import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env.dart';
import '../storage/token_store.dart';
import 'api_error.dart';

/// Dio instance provider.
final dioProvider = Provider<Dio>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  final client = DioClient(tokenStore: tokenStore);
  return client.dio;
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
  DioClient({required TokenStore tokenStore}) : _tokenStore = tokenStore {
    _dio = Dio(_createBaseOptions());
    _setupInterceptors();
  }

  final TokenStore _tokenStore;
  late final Dio _dio;

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
    if (Env.enableLogging) {
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

      if (error.response?.statusCode == 401 && !alreadyRetried) {
        if (await _refreshToken()) {
          try {
            final options = error.requestOptions;
            options.extra[_retryMarker] = true;
            final newToken = await _tokenStore.readAccessToken();
            if (newToken != null) {
              options.headers['Authorization'] = 'Bearer $newToken';
            }

            final response = await _dio.fetch(options);
            return handler.resolve(response);
          } catch (_) {
            // Retry also failed; fall through to logout below.
          }
        }
        // Refresh failed, or refresh succeeded but the retry still 401'd —
        // either way the session is unrecoverable on this backend.
        await _tokenStore.clear();
      } else if (error.response?.statusCode == 401 && alreadyRetried) {
        // Second 401 in the same request chain → don't try to refresh again.
        await _tokenStore.clear();
      }

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

  bool _isRefreshing = false;

  /// Attempt to refresh the access token.
  Future<bool> _refreshToken() async {
    if (_isRefreshing) return false; // Prevent concurrent refreshes
    _isRefreshing = true;

    try {
      final refreshToken = await _tokenStore.readRefreshToken();
      if (refreshToken == null) return false;

      // Use a new Dio instance to avoid interceptor loops
      final refreshDio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));

      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final newAccessToken = data['accessToken']?.toString();
        final newRefreshToken = data['refreshToken']?.toString();

        if (newAccessToken != null) {
          await _tokenStore.saveAccessToken(newAccessToken);
        }
        if (newRefreshToken != null) {
          await _tokenStore.saveRefreshToken(newRefreshToken);
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    } finally {
      _isRefreshing = false;
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
      message =
          data['message']?.toString() ??
          data['error']?.toString() ??
          data['detail']?.toString();
      code = data['code']?.toString();
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
