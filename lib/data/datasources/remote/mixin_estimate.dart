import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gbk_codec/gbk_codec.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../utils/cache_manager.dart';
import 'remote_dio_accessor.dart';

/// 净值与估值数据源 mixin
/// 职责：GZ 估值 API、批量估值、三级降级获取准确数据
mixin FundEstimateDataSource on RemoteDioAccessor {
  // ── 缓存 ──
  final CacheManager<Map<String, dynamic>> _gzCacheMgr =
      CacheManager(60 * 1000);

  /// 获取基金估值数据（GBK 编码 JSONP）
  /// 缓存策略：60秒TTL，每次请求前主动清理过期缓存
  Future<Map<String, dynamic>> fetchFundGZ(String code) async {
    _gzCacheMgr.cleanExpired();

    final cached = _gzCacheMgr.get(code);
    if (cached != null) {
      debugPrint('[API] GZ缓存命中: $code');
      return cached;
    }

    debugPrint('[API] GZ缓存未命中，请求: $code');
    try {
      final response = await dio.get(
        'https://fundgz.1234567.com.cn/js/$code.js',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data as Uint8List;
      final text = gbk.decode(bytes);
      final jsonStr = text.replaceFirst('jsonpgz(', '').replaceAll(');', '');
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;

      _gzCacheMgr.set(code, result);
      return result;
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('404') ||
          errStr.contains('403') ||
          errStr.contains('500') ||
          errStr.contains('502') ||
          errStr.contains('503')) {
        debugPrint('[API] GZ HTTP错误($code): $e, 跳过UTF-8降级');
        rethrow;
      }
      // 编码类错误降级 UTF-8
      try {
        final response = await dio.get(
          'https://fundgz.1234567.com.cn/js/$code.js',
          options: Options(responseType: ResponseType.plain),
        );
        final text = response.data as String;
        final jsonStr = text.replaceFirst('jsonpgz(', '').replaceAll(');', '');
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;

        _gzCacheMgr.set(code, result);
        return result;
      } catch (e2) {
        throw Exception('获取基金估值失败: $e2');
      }
    }
  }

  /// 获取基金估值（返回 FundEstimate 实体）
  Future<FundEstimate> fetchFundEstimate(String code) async {
    try {
      final gz = await fetchFundGZ(code);
      return FundEstimate(
        fundcode: code,
        name: gz['name'] ?? '',
        jzrq: gz['jzrq'] ?? '',
        dwjz: double.tryParse(gz['dwjz']?.toString() ?? '0') ?? 0.0,
        gsz: double.tryParse(gz['gsz']?.toString() ?? '0') ?? 0.0,
        gszzl: double.tryParse(gz['gszzl']?.toString() ?? '0') ?? 0.0,
        gztime: gz['gztime'] ?? '',
      );
    } catch (e) {
      debugPrint('[API] fetchFundEstimate error ($code): $e');
      return FundEstimate(
        fundcode: code,
        name: '',
        jzrq: '',
        dwjz: 0.0,
        gsz: 0.0,
        gszzl: 0.0,
        gztime: '',
      );
    }
  }

  /// 批量获取基金估值（并发请求，限制并发数为 5）
  Future<Map<String, FundEstimate>> fetchFundEstimates(
      List<String> codes) async {
    final result = <String, FundEstimate>{};
    const maxConcurrency = 5;

    for (var i = 0; i < codes.length; i += maxConcurrency) {
      final batch = codes.skip(i).take(maxConcurrency).toList();
      final futures = batch.map((code) async {
        final estimate = await fetchFundEstimate(code);
        return MapEntry(code, estimate);
      });
      final entries = await Future.wait(futures);
      for (final entry in entries) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// GZ 缓存清理（供 facade 调用）
  void clearGzCache() => _gzCacheMgr.clear();
}
