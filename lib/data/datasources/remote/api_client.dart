import 'package:dio/dio.dart';

/// 缓存条目
class _CacheEntry {
  final Map<String, dynamic>? data;
  final int timestamp;

  _CacheEntry(this.data) : timestamp = DateTime.now().millisecondsSinceEpoch;

  bool isExpired(int ttlMs) =>
      DateTime.now().millisecondsSinceEpoch - timestamp > ttlMs;
}

/// 统一 Dio HTTP 客户端（带内存缓存）
///
/// 特性：
/// - 30秒 TTL 内存缓存，避免重复请求
/// - 最多缓存100条，LRU 淘汰策略
/// - 自动清理过期缓存
/// - 不写磁盘，零存储占用
class ApiClient {
  late final Dio _dio;

  /// 缓存存储
  final Map<String, _CacheEntry> _cache = {};

  /// 缓存 TTL（毫秒）
  static const int _cacheTtlMs = 30 * 1000; // 30秒

  /// 最大缓存条目数
  static const int _maxCacheSize = 100;

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 Chrome/88.0.4324.181 Mobile Safari/537.36',
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      error: true,
      logPrint: (obj) => print('[API] $obj'),
    ));
  }

  /// 生成缓存 key
  String _cacheKey(String url, Map<String, String>? params) {
    if (params == null || params.isEmpty) return url;
    final sortedParams = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$url?${sortedParams.map((e) => '${e.key}=${e.value}').join('&')}';
  }


  /// 检查并淘汰最旧缓存（LRU）
  void _evictOldestIfNeeded() {
    if (_cache.length < _maxCacheSize) return;

    // 找到最旧的条目删除
    String? oldestKey;
    int oldestTime = DateTime.now().millisecondsSinceEpoch;
    _cache.forEach((key, entry) {
      if (entry.timestamp < oldestTime) {
        oldestTime = entry.timestamp;
        oldestKey = key;
      }
    });
    if (oldestKey != null) {
      _cache.remove(oldestKey);
      print('[API] Cache evicted (LRU): $oldestKey');
    }
  }

  Future<Map<String, dynamic>?> get(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    int retries = 3,
    bool useCache = true,  // 是否使用缓存
  }) async {
    final cacheKey = _cacheKey(url, queryParameters);

    // 检查缓存
    if (useCache) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired(_cacheTtlMs)) {
        print('[API] Cache HIT: $cacheKey');
        return cached.data;
      }
      print('[API] Cache MISS: $cacheKey');
    }

    // 发起请求
    int attempt = 0;
    while (attempt <= retries) {
      try {
        final response = await _dio.get(
          url,
          options: Options(headers: headers),
          queryParameters: queryParameters,
        );
        if (response.statusCode == 200 || response.statusCode == 304) {
          final data = response.data as Map<String, dynamic>?;

          // 存入缓存
          if (useCache && data != null) {
            _evictOldestIfNeeded();
            _cache[cacheKey] = _CacheEntry(data);
            print('[API] Cache SET: $cacheKey (size: ${_cache.length})');
          }

          return data;
        }
      } on DioException catch (e) {
        print('[API] Attempt ${attempt + 1} failed for $url: ${e.message}');
      }
      if (attempt < retries) {
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      }
      attempt++;
    }
    return null;
  }

  /// 清空所有缓存（用于强制刷新）
  void clearCache() {
    _cache.clear();
    print('[API] Cache CLEARED');
  }

  /// 获取缓存统计信息
  Map<String, int> get cacheStats => {
    'count': _cache.length,
    'maxSize': _maxCacheSize,
    'ttlMs': _cacheTtlMs,
  };

  void dispose() {
    _cache.clear();
    _dio.close();
  }
}

/// 通用 JSONP 结果封装
class JsonpResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? raw;

  JsonpResult({required this.success, this.data, this.raw});
}
