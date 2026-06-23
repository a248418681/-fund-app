import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../utils/cache_manager.dart';
import 'internal_models.dart';
import 'remote_dio_accessor.dart';

/// pingzhongdata 解析 mixin
/// 职责：获取并解析东方财富 pingzhongdata JS（净值走势、阶段涨幅、基金经理、行业配置、资产配置）
mixin PzDataDataSource on RemoteDioAccessor {
  // ── 缓存 ──
  final CacheManager<PzData> _pzCacheMgr = CacheManager(5 * 60 * 1000);

  /// 获取 pingzhongdata 详情数据（带缓存）
  Future<PzData> fetchPzData(String code) async {
    _pzCacheMgr.cleanExpired();

    final cached = _pzCacheMgr.get(code);
    if (cached != null) return cached;

    try {
      final response = await dio.get(
        'https://fund.eastmoney.com/pingzhongdata/$code.js',
        options: Options(responseType: ResponseType.plain),
      );
      var jsText = response.data as String;
      // 去掉 UTF-8 BOM
      if (jsText.codeUnitAt(0) == 0xFEFF ||
          (jsText.length >= 3 && jsText[0] == '\uFEFF')) {
        jsText = jsText.substring(1);
      } else if (jsText.length >= 3 &&
          jsText.codeUnitAt(0) == 0xEF &&
          jsText.codeUnitAt(1) == 0xBB &&
          jsText.codeUnitAt(2) == 0xBF) {
        jsText = jsText.substring(3);
      }
      final data = _parsePingzhongData(jsText);
      _pzCacheMgr.set(code, data);
      return data;
    } catch (e) {
      throw Exception('获取 pingzhongdata 失败: $e');
    }
  }

  /// 解析 pingzhongdata JS 变量
  PzData _parsePingzhongData(String jsText) {
    final data = PzData();

    data.fSName = _extractVar(jsText, 'fS_name');
    data.fSCode = _extractVar(jsText, 'fS_code');
    data.fundSourceRate = _extractVarDouble(jsText, 'fund_sourceRate');
    data.fundRate = _extractVarDouble(jsText, 'fund_Rate');
    data.fundMinsg = _extractVarDouble(jsText, 'fund_minsg');

    data.syl1n = _extractVarDouble(jsText, 'syl_1n');
    data.syl6y = _extractVarDouble(jsText, 'syl_6y');
    data.syl3y = _extractVarDouble(jsText, 'syl_3y');
    data.syl1y = _extractVarDouble(jsText, 'syl_1y');

    // 净值走势
    final netWorthMatch = RegExp(
      r'Data_netWorthTrend\s*=\s*(\[[\s\S]*?\]);',
    ).firstMatch(jsText);
    if (netWorthMatch != null) {
      try {
        data.netWorthTrend = jsonDecode(netWorthMatch.group(1)!) as List;
      } catch (e) {
        debugPrint('[_PzData] netWorthTrend parse error: $e');
      }
    }

    // 货币基金：每万份收益
    final millionIncomeMatch = RegExp(
      r'Data_millionCopiesIncome\s*=\s*(\[[\s\S]*?\]);',
    ).firstMatch(jsText);
    if (millionIncomeMatch != null) {
      try {
        data.millionCopiesIncome =
            jsonDecode(millionIncomeMatch.group(1)!) as List;
      } catch (e) {
        debugPrint('[_PzData] millionCopiesIncome parse error: $e');
      }
    }

    // 基金经理
    _parseManagers(jsText, data);

    // 行业配置
    try {
      final mc = RegExp(r'Data_IndustryAllocation\s*=\s*(\{[\s\S]*?\}\s*);')
          .firstMatch(jsText);
      if (mc != null) {
        final parsed = jsonDecode(mc.group(1)!);
        if (parsed is Map && parsed['series'] is List) {
          final series = parsed['series'] as List;
          if (series.isNotEmpty && series[0]['data'] is List) {
            data.industryItems = series[0]['data'] as List;
          }
        }
      }
    } catch (e) {
      debugPrint('[_PzData] industryItems error: $e');
    }

    // 资产配置
    try {
      final mc = RegExp(r'Data_assetAllocation\s*=\s*(\{[\s\S]*?\}\s*);')
          .firstMatch(jsText);
      if (mc != null) {
        final parsed = jsonDecode(mc.group(1)!);
        if (parsed is Map && parsed['series'] is List) {
          data.assetSeries = parsed['series'] as List;
        }
      }
    } catch (e) {
      debugPrint('[_PzData] assetAllocation parse error: $e');
    }

    debugPrint('[_PzData] fSName=${data.fSName}, '
        'netWorth=${data.netWorthTrend.length}, '
        'managers=${data.managers.length}, '
        'industryItems=${data.industryItems.length}, '
        'assetSeries=${data.assetSeries.length}');

    return data;
  }

  void _parseManagers(String jsText, PzData data) {
    try {
      List<dynamic>? managersResult;

      // 方法1：手写深度追踪——可靠提取嵌套 JSON 数组
      final mc = RegExp(r'Data_currentFundManager\s*=\s*\[').firstMatch(jsText);
      if (mc != null) {
        int start = mc.end;
        int depth = 1;
        int i = start;
        bool inStr = false;
        while (i < jsText.length && depth > 0) {
          final c = jsText[i];
          if (c == '"') {
            int bsCount = 0;
            int j = i - 1;
            while (j >= start && jsText[j] == '\\') {
              bsCount++;
              j--;
            }
            if (bsCount % 2 == 0) {
              inStr = !inStr;
            }
          } else if (!inStr) {
            if (c == '[' || c == '{') {
              depth++;
            } else if (c == ']' || c == '}') {
              depth--;
            }
          }
          i++;
        }
        if (depth == 0) {
          String jsonStr = jsText.substring(start - 1, i).trim();
          jsonStr = jsonStr
              .replaceAll('\r\n', ' ')
              .replaceAll('\n', ' ')
              .replaceAll('\r', ' ')
              .replaceAll('\t', ' ');
          try {
            final decoded = jsonDecode(jsonStr);
            if (decoded is List) {
              managersResult = decoded;
            } else if (decoded is Map) {
              managersResult = [decoded];
            }
          } catch (e) {
            debugPrint('[_PzData] managers jsonDecode failed: $e');
          }
        }
      }

      // 方法2：回退到简单字段提取
      if (managersResult == null) {
        try {
          final nameMatches =
              RegExp(r'"name"\s*:\s*"([^"]+)"').allMatches(jsText);
          final idMatches =
              RegExp(r'"id"\s*:\s*"?([^"\r\n,}\]]+)"?').allMatches(jsText);
          final names = nameMatches.map((m) => m.group(1)!).toList();
          final ids = idMatches.map((m) => m.group(1)!).toList();
          if (names.isNotEmpty) {
            managersResult = List.generate(
              names.length.clamp(0, ids.length),
              (i) => {'name': names[i], 'id': ids.length > i ? ids[i] : ''},
            );
          }
        } catch (e) {
          debugPrint('[_PzData] managers fallback failed: $e');
        }
      }

      data.managers = managersResult ?? [];
    } catch (e) {
      debugPrint('[_PzData] managers error: $e');
    }
  }

  String? _extractVar(String text, String varName) {
    final match = RegExp('$varName\\s*=\\s*"([^"]*)"').firstMatch(text);
    return match?.group(1);
  }

  double? _extractVarDouble(String text, String varName) {
    var match = RegExp('$varName\\s*=\\s*"([^"]*)"').firstMatch(text);
    if (match != null) return double.tryParse(match.group(1)!);
    match = RegExp('$varName\\s*=\\s*([\\d.]+)').firstMatch(text);
    if (match != null) return double.tryParse(match.group(1)!);
    return null;
  }

  /// 获取净值历史
  Future<List<NetValueRecord>> fetchNetValueHistory(String code,
      {int days = 90}) async {
    try {
      final pz = await fetchPzData(code);
      final trend = pz.netWorthTrend;
      if (trend.isEmpty) return [];

      final startIdx = trend.length > days ? trend.length - days : 0;
      final recentTrend = trend.sublist(startIdx);

      return recentTrend.map((item) {
        final map = item as Map<String, dynamic>;
        final xValue = map['x'];
        String dateStr;
        if (xValue is int) {
          final date = DateTime.fromMillisecondsSinceEpoch(xValue);
          dateStr =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        } else {
          dateStr = xValue?.toString() ?? '';
        }
        return NetValueRecord(
          date: dateStr,
          netValue: (map['y'] ?? map['unitNav'] ?? 0).toDouble(),
          totalValue: (map['equityReturn'] ?? 0).toDouble(),
          changeRate: (map['equityReturn'] ?? 0).toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchNetValueHistory error ($code): $e');
      return [];
    }
  }

  /// 获取阶段涨幅
  Future<List<PeriodReturn>> fetchPeriodReturns(String code) async {
    try {
      final pz = await fetchPzData(code);
      return [
        PeriodReturn(period: '1m', label: '近1月', returnRate: pz.syl1y ?? 0.0),
        PeriodReturn(period: '3m', label: '近3月', returnRate: pz.syl3y ?? 0.0),
        PeriodReturn(period: '6m', label: '近6月', returnRate: pz.syl6y ?? 0.0),
        PeriodReturn(period: '1y', label: '近1年', returnRate: pz.syl1n ?? 0.0),
      ];
    } catch (e) {
      debugPrint('[API] fetchPeriodReturns error ($code): $e');
      return [];
    }
  }

  /// 获取基金经理信息
  Future<List<FundManagerInfo>> fetchFundManagerInfo(String code) async {
    try {
      final pz = await fetchPzData(code);
      return pz.managers.map((item) {
        final map = item as Map<String, dynamic>;
        return FundManagerInfo(
          id: (map['id'] ?? '').toString(),
          name: (map['name'] ?? '').toString(),
          photo: (map['photo'] ?? '').toString(),
          company: '',
          workingDays: 0,
          managedScale: 0.0,
          managedCount: 0,
          bestReturn: 0.0,
          annualReturn: (map['annualReturn'] ?? 0).toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchFundManagerInfo error ($code): $e');
      return [];
    }
  }

  /// PZ 缓存清理（供 facade 调用）
  void clearPzCache() => _pzCacheMgr.clear();
}
