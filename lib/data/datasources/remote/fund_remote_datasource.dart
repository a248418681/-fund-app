import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gbk_codec/gbk_codec.dart';
import '../../../domain/entities/fund_entity.dart';

/// 缓存条目（带时间戳）
class _CacheEntry<T> {
  final T data;
  final int timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now().millisecondsSinceEpoch;
  
  bool isExpired(int ttlMs) => 
      DateTime.now().millisecondsSinceEpoch - timestamp > ttlMs;
}

/// 天天基金远程数据源
class FundRemoteDataSource {
  final Dio _dio;
  
  /// pingzhongdata 缓存（无TTL，详情页停留期间有效）
  final Map<String, _PzData> _pzCache = {};
  
  /// 估值数据缓存（60秒TTL，匹配刷新频率）
  final Map<String, _CacheEntry<Map<String, dynamic>>> _gzCache = {};
  static const int _gzCacheTtl = 60 * 1000; // 60秒

  FundRemoteDataSource(this._dio);
  
  /// 清理过期的估值缓存
  void _cleanExpiredGzCache() {
    final expiredKeys = <String>[];
    _gzCache.forEach((key, entry) {
      if (entry.isExpired(_gzCacheTtl)) {
        expiredKeys.add(key);
      }
    });
    for (final key in expiredKeys) {
      _gzCache.remove(key);
    }
    if (expiredKeys.isNotEmpty) {
      debugPrint('[API] GZ缓存清理: ${expiredKeys.length}条过期, 剩余${_gzCache.length}条');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 核心数据获取
  // ══════════════════════════════════════════════════════════════════════

  /// 获取基金估值数据（GBK 编码 JSONP）
  /// 缓存策略：60秒TTL，每次请求前主动清理过期缓存
  Future<Map<String, dynamic>> fetchFundGZ(String code) async {
    // 1. 主动清理过期缓存
    _cleanExpiredGzCache();
    
    // 2. 检查缓存
    final cached = _gzCache[code];
    if (cached != null) {
      debugPrint('[API] GZ缓存命中: $code');
      return cached.data;
    }
    
    // 3. 缓存未命中，发起请求
    debugPrint('[API] GZ缓存未命中，请求: $code');
    try {
      final response = await _dio.get(
        'https://fundgz.1234567.com.cn/js/$code.js',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data as Uint8List;
      final text = gbk.decode(bytes);
      final jsonStr = text.replaceFirst('jsonpgz(', '').replaceAll(');', '');
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      // 4. 存入缓存
      _gzCache[code] = _CacheEntry(result);
      return result;
    } catch (e) {
      // 仅对编码类错误降级 UTF-8（GBK 解码失败时）
      // 404/403/5xx 不重试 — 不是编码问题，重试无意义
      final errStr = e.toString();
      if (errStr.contains('404') || errStr.contains('403') ||
          errStr.contains('500') || errStr.contains('502') || errStr.contains('503')) {
        debugPrint('[API] GZ HTTP错误($code): $e, 跳过UTF-8降级');
        rethrow;
      }
      try {
        final response = await _dio.get(
          'https://fundgz.1234567.com.cn/js/$code.js',
          options: Options(responseType: ResponseType.plain),
        );
        final text = response.data as String;
        final jsonStr = text.replaceFirst('jsonpgz(', '').replaceAll(');', '');
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        
        // 存入缓存
        _gzCache[code] = _CacheEntry(result);
        return result;
      } catch (e2) {
        throw Exception('获取基金估值失败: $e2');
      }
    }
  }

  /// 获取 pingzhongdata 详情数据（带缓存）
  Future<_PzData> _fetchPzData(String code) async {
    if (_pzCache.containsKey(code)) {
      return _pzCache[code]!;
    }
    
    try {
      // pingzhongdata 返回 UTF-8 (带 BOM: EF BB BF)
      final response = await _dio.get(
        'https://fund.eastmoney.com/pingzhongdata/$code.js',
        options: Options(responseType: ResponseType.plain),
      );
      var jsText = response.data as String;
      // 去掉 UTF-8 BOM (EF BB BF) 如果存在
      if (jsText.codeUnitAt(0) == 0xFEFF || 
          (jsText.length >= 3 && jsText[0] == '\uFEFF')) {
        // BOM as character
        jsText = jsText.substring(1);
      } else if (jsText.length >= 3 && 
          jsText.codeUnitAt(0) == 0xEF && 
          jsText.codeUnitAt(1) == 0xBB && 
          jsText.codeUnitAt(2) == 0xBF) {
        // Raw BOM bytes that got decoded as 3 chars
        jsText = jsText.substring(3);
      }
      final data = _parsePingzhongData(jsText);
      _pzCache[code] = data;
      return data;
    } catch (e) {
      throw Exception('获取 pingzhongdata 失败: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // pingzhongdata 解析
  // ══════════════════════════════════════════════════════════════════════

  /// 解析 pingzhongdata JS 变量
  _PzData _parsePingzhongData(String jsText) {
    final data = _PzData();

    // ── 基础变量（var name = "value" 或 var name = number）──
    data.fSName = _extractVar(jsText, 'fS_name');
    data.fSCode = _extractVar(jsText, 'fS_code');
    data.fundSourceRate = _extractVarDouble(jsText, 'fund_sourceRate');
    data.fundRate = _extractVarDouble(jsText, 'fund_Rate');
    data.fundMinsg = _extractVarDouble(jsText, 'fund_minsg');

    // ── 阶段涨幅 ──
    data.syl1n = _extractVarDouble(jsText, 'syl_1n');  // 近1年
    data.syl6y = _extractVarDouble(jsText, 'syl_6y');  // 近6月
    data.syl3y = _extractVarDouble(jsText, 'syl_3y');  // 近3月
    data.syl1y = _extractVarDouble(jsText, 'syl_1y');  // 近1月

    // ── 净值走势：Data_netWorthTrend ──
    final netWorthMatch = RegExp(
      r'Data_netWorthTrend\s*=\s*(\[[\s\S]*?\]);',
    ).firstMatch(jsText);
    if (netWorthMatch != null) {
      try {
        data.netWorthTrend = jsonDecode(netWorthMatch.group(1)!) as List;
      } catch (e) { debugPrint('[_PzData] netWorthTrend parse error: $e'); }
    }

    // ── 货币基金：每万份收益 Data_millionCopiesIncome ──
    final millionIncomeMatch = RegExp(
      r'Data_millionCopiesIncome\s*=\s*(\[[\s\S]*?\]);',
    ).firstMatch(jsText);
    if (millionIncomeMatch != null) {
      try {
        data.millionCopiesIncome = jsonDecode(millionIncomeMatch.group(1)!) as List;
      } catch (e) { debugPrint('[_PzData] millionCopiesIncome parse error: $e'); }
    }

    // ── 基金经理：Data_currentFundManager ──
    // 两次尝试：先正则非贪婪 + 引擎回溯（稳健），失败再深度追踪兜底
    try {
      List<dynamic>? managersResult;

      // 方法1（主路径）：手写深度追踪——可靠提取嵌套 JSON 数组
      // 注：正则 \[.*?\]; 在嵌套 JSON 场景下总是失败，已移除
      {
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
              while (j >= start && jsText[j] == '\\') { bsCount++; j--; }
              if (bsCount % 2 == 0) inStr = !inStr;
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
              debugPrint('[_PzData] managers depth tracker jsonDecode failed: $e');
            }
          } else {
            debugPrint('[_PzData] managers depth tracker: unmatched brackets, depth=$depth');
          }
        }
      }

      // 方法2：深度追踪失败时回退到简单字段提取（仅取 name/id）
      if (managersResult == null) {
        try {
          debugPrint('[_PzData] managers: falling back to simple field extraction');
          final nameMatches = RegExp(r'"name"\s*:\s*"([^"]+)"').allMatches(jsText);
          final idMatches = RegExp(r'"id"\s*:\s*"?([^"\r\n,}\]]+)"?').allMatches(jsText);
          final names = nameMatches.map((m) => m.group(1)!).toList();
          final ids = idMatches.map((m) => m.group(1)!).toList();
          if (names.isNotEmpty) {
            managersResult = List.generate(
              names.length.clamp(0, ids.length),
              (i) => {'name': names[i], 'id': ids.length > i ? ids[i] : ''},
            );
            debugPrint('[_PzData] managers extracted ${managersResult.length} via simple fallback');
          }
        } catch (e) {
          debugPrint('[_PzData] managers simple fallback also failed: $e');
        }
      }

      data.managers = managersResult ?? [];
      debugPrint('[_PzData] managers=${data.managers.length}, '
          'sample=${data.managers.isNotEmpty ? data.managers.first.toString().substring(0, 80) : "empty"}');
    } catch (e) {
      debugPrint('[_PzData] managers error: $e');
    }

    // ── 行业配置：Data_IndustryAllocation（东方财富可能无此数据）──
    try {
      // 贪婪匹配到下一个 var 声明
      final mc = RegExp(r'Data_IndustryAllocation\s*=\s*(\{[\s\S]*?\}\s*);').firstMatch(jsText);
      debugPrint('[_PzData] Data_IndustryAllocation: ${mc != null ? "match" : "null"}');
      if (mc != null) {
        final parsed = jsonDecode(mc.group(1)!);
        if (parsed is Map && parsed['series'] is List) {
          final series = parsed['series'] as List;
          if (series.isNotEmpty && series[0]['data'] is List) {
            data.industryItems = series[0]['data'] as List;
          }
        }
        debugPrint('[_PzData] industryItems=${data.industryItems.length}');
      }
    } catch (e) {
      debugPrint('[_PzData] industryItems error: $e');
    }

    // ── 资产配置：Data_assetAllocation ──
    try {
      final mc = RegExp(r'Data_assetAllocation\s*=\s*(\{[\s\S]*?\}\s*);').firstMatch(jsText);
      if (mc != null) {
        final parsed = jsonDecode(mc.group(1)!);
        if (parsed is Map && parsed['series'] is List) {
          data.assetSeries = parsed['series'] as List;
        }
      }
    } catch (e) { debugPrint('[_PzData] assetAllocation parse error: $e'); }

    // ── 调试日志 ──
    debugPrint('[_PzData] fSName=${data.fSName}, '
        'netWorth=${data.netWorthTrend.length}, '
        'managers=${data.managers.length}, '
        'industryItems=${data.industryItems.length}, '
        'assetSeries=${data.assetSeries.length}');

    return data;
  }

  /// 提取字符串变量：var name = "value";
  String? _extractVar(String text, String varName) {
    final match = RegExp(
      '$varName\\s*=\\s*"([^"]*)"',
    ).firstMatch(text);
    return match?.group(1);
  }

  /// 提取数字变量：var name = 1.23; 或 var name = "1.23";
  double? _extractVarDouble(String text, String varName) {
    // 先尝试带引号
    var match = RegExp(
      '$varName\\s*=\\s*"([^"]*)"',
    ).firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    // 再尝试无引号
    match = RegExp(
      '$varName\\s*=\\s*([\\d.]+)',
    ).firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // 公开 API 方法
  // ══════════════════════════════════════════════════════════════════════

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

  /// 批量获取基金估值
  Future<Map<String, FundEstimate>> fetchFundEstimates(List<String> codes) async {
    final result = <String, FundEstimate>{};
    for (final code in codes) {
      result[code] = await fetchFundEstimate(code);
    }
    return result;
  }

  /// 获取基金准确数据（详情页核心）
  /// 获取基金准确数据（三级降级：GZ+PZ → 仅PZ → 蛋卷）
  ///
  /// Level 1: 天天基金 GZ(估值) + PZ(详情) 并行 → 最完整数据
  /// Level 2: GZ 失败(如QDII 404) → 仅 PZ → 有净值无实时估值
  /// Level 3: PZ 也失败 → 蛋卷 API → 有基础数据+重仓股
  /// Level 4: 全部失败 → 抛异常
  Future<FundAccurateData> fetchFundAccurateData(String code) async {
    // ── Level 1: GZ + PZ 并行 ──
    Map<String, dynamic>? gz;
    _PzData? pz;

    try {
      gz = await fetchFundGZ(code);
    } catch (e) {
      debugPrint('[API] GZ失败($code): $e, 降级为仅PZ');
    }

    try {
      pz = await _fetchPzData(code);
    } catch (e) {
      debugPrint('[API] PZ失败($code): $e');
    }

    // GZ 成功 → 最优路径
    if (gz != null) {
      return FundAccurateData(
        code: code,
        name: pz?.fSName ?? gz['name'] ?? '',
        nav: double.tryParse(gz['dwjz']?.toString() ?? '0') ?? 0.0,
        navDate: (gz['jzrq'] ?? '').replaceAll('-', ''),
        navChange: 0.0,
        estimate: double.tryParse(gz['gsz']?.toString() ?? '0') ?? 0.0,
        estimateTime: gz['gztime'] ?? '',
        estimateChange: double.tryParse(gz['gszzl']?.toString() ?? '0') ?? 0.0,
        prevClose: 0.0,
        currentValue: double.tryParse(gz['gsz']?.toString() ?? '0') ?? 0.0,
        dayChange: pz?.netWorthTrend.isNotEmpty == true
            ? ((pz!.netWorthTrend.last as Map<String, dynamic>)['equityReturn'] ?? 0).toDouble()
            : 0.0,
        dataSource: 'gz+pz',
        fundType: '',
        company: '',
        manager: pz?.managers.isNotEmpty == true ? pz!.managers[0]['name'] : null,
      );
    }

    // ── Level 2: 仅 PZ（有净值无实时估值） ──
    if (pz != null) {
      final navList = pz.netWorthTrend;
      double lastNav = 0;
      String lastNavDate = '';
      double prevNav = 0;
      if (navList.length >= 2) {
        final last = navList[navList.length - 1] as Map<String, dynamic>;
        final prev = navList[navList.length - 2] as Map<String, dynamic>;
        lastNav = (last['y'] ?? 0).toDouble();
        prevNav = (prev['y'] ?? 0).toDouble();
        final xVal = last['x'];
        if (xVal is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(xVal);
          lastNavDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      } else if (navList.length == 1) {
        final last = navList[0] as Map<String, dynamic>;
        lastNav = (last['y'] ?? 0).toDouble();
        final xVal = last['x'];
        if (xVal is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(xVal);
          lastNavDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      }

      final dayChg = (prevNav > 0 && lastNav > 0) ? (lastNav - prevNav) / prevNav * 100 : 0.0;

      // 货币基金等可能取不到有效净值，降级到蛋卷API
      if (lastNav > 0) {
        debugPrint('[API] 仅PZ降级($code): nav=$lastNav, dayChange=${dayChg.toStringAsFixed(2)}%');

        return FundAccurateData(
          code: code,
          name: pz.fSName ?? '',
          nav: lastNav,
          navDate: lastNavDate.replaceAll('-', ''),
          navChange: 0.0,
          estimate: lastNav,
          estimateTime: '',
          estimateChange: dayChg,
          prevClose: prevNav,
          currentValue: lastNav,
          dayChange: dayChg,
          dataSource: 'pz-only',
          fundType: '',
          company: '',
          manager: pz.managers.isNotEmpty ? pz.managers[0]['name'] : null,
        );
      }

      // ── 货币基金兜底：尝试 Data_millionCopiesIncome（每万份收益）──
      if (pz.millionCopiesIncome.isNotEmpty) {
        final incomeList = pz.millionCopiesIncome;
        final lastIncome = incomeList[incomeList.length - 1];
        final lastY = (lastIncome is Map ? lastIncome['y'] : (lastIncome as List)[1])?.toDouble() ?? 0.0;
        final lastX = lastIncome is Map ? lastIncome['x'] : (lastIncome as List)[0];
        String incomeDate = lastNavDate;
        if (lastX is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(lastX);
          incomeDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
        const navUnit = 0.0;
        debugPrint('[API] 货币基金PZ降级($code): millionCopiesIncome=${incomeList.length}, lastY=$lastY');
        return FundAccurateData(
          code: code,
          name: pz.fSName ?? '',
          nav: navUnit,
          navDate: incomeDate.replaceAll('-', ''),
          navChange: 0.0,
          estimate: navUnit,
          estimateTime: '',
          estimateChange: 0.0,
          prevClose: navUnit,
          currentValue: navUnit,
          dayChange: 0.0,
          dataSource: 'pz-million',
          fundType: '',
          company: '',
          manager: pz.managers.isNotEmpty ? pz.managers[0]['name'] : null,
        );
      }

      debugPrint('[API] PZ降级($code): NAV=0且无millionCopiesIncome, 继续降级至蛋卷API');
    }

    // ── Level 3: 蛋卷 API 降级 ──
    try {
      final dj = await _fetchDjData(code);
      if (dj != null) {
        debugPrint('[API] 蛋卷降级($code): stocks=${dj.stockList.length}');
        return FundAccurateData(
          code: code,
          name: '',  // 蛋卷 detail 无基金名，由 BLoC 侧保留
          nav: 0,
          navDate: '',
          navChange: 0.0,
          estimate: 0,
          estimateTime: '',
          estimateChange: 0.0,
          prevClose: 0.0,
          currentValue: 0,
          dayChange: 0.0,
          dataSource: 'danjuan',
          fundType: '',
          company: '',
        );
      }
    } catch (e) {
      debugPrint('[API] 蛋卷降级也失败($code): $e');
    }

    // ── 全部失败 ──
    throw Exception('获取基金数据失败：所有数据源均不可用($code)');
  }

  // ═══════════════════════════════════════════════════════════════
  // 净值历史与阶段回报
  // ═══════════════════════════════════════════════════════════════

  /// 获取净值历史（从 pingzhongdata）
  Future<List<NetValueRecord>> fetchNetValueHistory(String code, {int days = 90}) async {
    try {
      final pz = await _fetchPzData(code);
      final trend = pz.netWorthTrend;
      if (trend.isEmpty) return [];

      // 取最近 days 天
      final startIdx = trend.length > days ? trend.length - days : 0;
      final recentTrend = trend.sublist(startIdx);

      return recentTrend.map((item) {
        final map = item as Map<String, dynamic>;
        // x 是时间戳（毫秒），需要转换为日期字符串
        final xValue = map['x'];
        String dateStr;
        if (xValue is int) {
          // 时间戳转换为日期
          final date = DateTime.fromMillisecondsSinceEpoch(xValue);
          dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

  /// 获取阶段涨幅（从 pingzhongdata）
  Future<List<PeriodReturn>> fetchPeriodReturns(String code) async {
    try {
      final pz = await _fetchPzData(code);
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

  // ═══════════════════════════════════════════════════════════════
  // 持仓查询（东方财富 + 腾讯行情）
  // ═══════════════════════════════════════════════════════════════

  /// 获取重仓股（东方财富，已弃用 - 降级用）
  Future<List<StockHolding>> fetchStockHoldings(String code) async {
    return fetchStockHoldingsWithInfo(code);
  }

  /// 基金经理信息（从 pingzhongdata）

  /// 获取重仓股 HTML（东方财富）
  Future<String?> _fetchStockHoldingsHtml(String code) async {
    try {
      final response = await _dio.get(
        'https://fundf10.eastmoney.com/FundArchivesDatas.aspx',
        queryParameters: {
          'type': 'jjcc',
          'code': code,
          'topline': '10',
          'year': '',
          'month': '',
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://fundf10.eastmoney.com/',
            'User-Agent': 'Mozilla/5.0',
          },
        ),
      );

      var text = response.data.toString();
      debugPrint('[_fetchStockHoldingsHtml] raw first 200: ${text.substring(0, text.length.clamp(0, 200))}');

      // 可能是 JSONP 包装: callback(" <html content> ")
      // 尝试提取出 HTML 部分
      final jsonpMatch = RegExp(r'''\(["'](.+?)["']\)''', dotAll: true)
          .firstMatch(text);
      if (jsonpMatch != null) {
        text = jsonpMatch.group(1) ?? text;
        debugPrint('[_fetchStockHoldingsHtml] after JSONP strip, first 200: ${text.substring(0, text.length.clamp(0, 200))}');
      }

      return text;
    } catch (e) {
      debugPrint('[_fetchStockHoldingsHtml] error: $e');
      return null;
    }
  }

  /// 解析重仓股 HTML（东方财富格式：纯文本+链接，非表格）
  /// 格式示例: 1[00700](//quote.eastmoney.com/unify/r/116.00700)[腾讯控股]...[9.98%]...[572.00]...[309,468.46]
  List<_StockRaw> _parseStockHoldingsHtml(String html) {
    final holdings = <_StockRaw>[];

    // 匹配每个持仓的链接，支持股票和债券两种格式:
    // 股票: //quote.eastmoney.com/unify/r/MARKET.CODE (116.00700 / 1.600519 / 0.000858)
    // 债券: //quote.eastmoney.com/bond/sh122366.html 或 sz112475.html
    final stockRegex = RegExp(r'//quote\.eastmoney\.com/unify/r/\d+\.(\d{5,6})');
    final bondRegex = RegExp(r'//quote\.eastmoney\.com/bond/(?:sh|sz)(\d{6})\.html');
    // 提取百分比
    final pctRegex = RegExp(r'([\d\.]+)%');
    // 提取数字（万股、万元）
    final numRegex = RegExp(r'([\d,\.]+)');

    // 合并股票和债券匹配
    final allMatches = <RegExpMatch>[];
    final matchTypes = <String>[]; // 'stock' or 'bond'
    for (final m in stockRegex.allMatches(html)) {
      allMatches.add(m);
      matchTypes.add('stock');
    }
    for (final m in bondRegex.allMatches(html)) {
      allMatches.add(m);
      matchTypes.add('bond');
    }
    // 按位置排序
    final indexed = allMatches.asMap().entries.toList()
      ..sort((a, b) => a.value.start.compareTo(b.value.start));
    final sortedMatches = indexed.map((e) => MapEntry(e.value, matchTypes[e.key])).toList();

    debugPrint('[_parseStockHoldingsHtml] codes found: ${sortedMatches.length} (stock=${matchTypes.where((t) => t == 'stock').length}, bond=${matchTypes.where((t) => t == 'bond').length})');

    // 用序号分割，每个股票占一段
    // 格式: 序号 | 代码链接 | 名称 | ... | 占比% | 持股数 | 市值 | 变化
    // 先提取所有数字，然后按股票分配

    // 策略：从 HTML 中找到每个股票的锚点（序号+代码），然后往后找 % 和数字
    for (var i = 0; i < sortedMatches.length; i++) {
      final cm = sortedMatches[i].key;
      final assetType = sortedMatches[i].value;
      final stockCode = cm.group(1) ?? '';
      if (stockCode.isEmpty) continue;

      // 从这个代码位置往后搜索 500 字符
      final start = cm.start;
      final window = html.substring(start, (start + 500).clamp(0, html.length));

      // 找第一个 %（这是持仓比例）
      final pctMatch = pctRegex.firstMatch(window);
      if (pctMatch == null) continue;
      final ratio = double.tryParse(pctMatch.group(1)?.replaceAll(',', '') ?? '') ?? 0.0;

      // 在 % 之后找两个数字（持股数、市值）
      final afterPct = window.substring(pctMatch.end);
      final numsInRow = numRegex.allMatches(afterPct).take(5).toList();
      // 取前两个数字
      String shares = '0', amount = '0';
      if (numsInRow.isNotEmpty) shares = numsInRow[0].group(1) ?? '0';
      if (numsInRow.length > 1) amount = numsInRow[1].group(1) ?? '0';

      // 找股票名称：在 `](url)[名称](` 模式中，名称在两个链接之间
      // 格式: ...](//quote...)[腾讯控股](//quote...)
      final nameInLink = RegExp(r'\]\[([^[\]]{2,20})\]\(').firstMatch(window);
      final stockName = nameInLink?.group(1)?.trim() ?? (assetType == 'bond' ? '债券$stockCode' : '股票$stockCode');

      // 较上期变化：找 +/- 符号
      final changeMatch = RegExp(r'([+\-][\d\.]+%)').firstMatch(afterPct);
      final change = changeMatch?.group(1) ?? '--';

      debugPrint('[_parseStockHoldingsHtml] $stockCode $stockName (${assetType == 'bond' ? '债券' : '股票'}) ratio=$ratio shares=$shares amount=$amount change=$change');

      holdings.add(_StockRaw(
        stockCode: stockCode,
        stockName: assetType == 'bond' ? '$stockName(债券)' : stockName,
        holdingRatio: ratio,
        holdingAmount: amount.replaceAll(',', ''),
        changeFromLast: change,
      ));
    }

    debugPrint('[_parseStockHoldingsHtml] total: ${holdings.length}');
    return holdings;
  }

  /// 获取基金经理信息
  Future<List<FundManagerInfo>> fetchFundManagerInfo(String code) async {
    try {
      final pz = await _fetchPzData(code);
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

  // ══════════════════════════════════════════════════════════════════════
  // 股票行情（腾讯 API）
  // ══════════════════════════════════════════════════════════════════════

  /// 获取股票实时行情
  Future<Map<String, dynamic>?> fetchStockQuote(String stockCode) async {
    try {
      String prefix = stockCode.startsWith('6') || stockCode.startsWith('68') ? 'sh' : 'sz';
      // qt.gtimg.cn 返回 GBK 编码
      final response = await _dio.get('https://qt.gtimg.cn/q=$prefix$stockCode',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data as Uint8List;
      final text = gbk.decode(bytes);
      final match = RegExp(r'"(.*?)"').firstMatch(text);
      if (match == null) return null;
      final parts = match.group(1)!.split('~');
      if (parts.length < 35) return null;
      return {
        'name': parts[1],
        'code': parts[2],
        'price': double.tryParse(parts[3]),
        'close': double.tryParse(parts[4]),
        'open': double.tryParse(parts[5]),
        'high': double.tryParse(parts[33]),
        'low': double.tryParse(parts[34]),
        'change': double.tryParse(parts[31]),
        'changePercent': double.tryParse(parts[32]),
        'volume': parts[6],
        'amount': parts[37],
      };
    } catch (e) {
      debugPrint('[API] fetchStockQuote error ($stockCode): $e');
      return null;
    }
  }

  /// 批量获取股票行情
  Future<Map<String, Map<String, dynamic>>> fetchStockQuotesBatch(List<String> stockCodes) async {
    if (stockCodes.isEmpty) return {};
    
    try {
      // 腾讯支持批量查询：q=sh600519,sz000001,...
      final symbols = stockCodes.map((code) {
        String prefix = code.startsWith('6') || code.startsWith('68') ? 'sh' : 'sz';
        return '$prefix$code';
      }).join(',');
      
      // qt.gtimg.cn 返回 GBK 编码
      final response = await _dio.get('https://qt.gtimg.cn/q=$symbols',
        options: Options(responseType: ResponseType.bytes),
      );
      final qBytes = response.data as Uint8List;
      final text = gbk.decode(qBytes);
      final result = <String, Map<String, dynamic>>{};
      
      // 解析多个股票
      final matches = RegExp(r'"(.*?)"').allMatches(text);
      for (final match in matches) {
        final parts = match.group(1)!.split('~');
        if (parts.length < 35) continue;
        
        final code = parts[2];
        result[code] = {
          'name': parts[1],
          'code': code,
          'price': double.tryParse(parts[3]),
          'close': double.tryParse(parts[4]),
          'changePercent': double.tryParse(parts[32]),
        };
      }
      return result;
    } catch (e) {
      debugPrint('[API] fetchStockQuotesBatch error: $e');
      return {};
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 市场数据
  // ══════════════════════════════════════════════════════════════════════

  /// 获取大盘指数
  Future<List<MarketIndex>> fetchMarketIndices() async {
    try {
      // 上证指数、深证成指、创业板指、沪深300
      final codes = ['sh000001', 'sz399001', 'sz399006', 'sh000300'];
      // qt.gtimg.cn 返回 GBK 编码
      final response = await _dio.get('https://qt.gtimg.cn/q=${codes.join(',')}',
        options: Options(responseType: ResponseType.bytes),
      );
      final idxBytes = response.data as Uint8List;
      final text = gbk.decode(idxBytes);
      
      final result = <MarketIndex>[];
      final matches = RegExp(r'"(.*?)"').allMatches(text);
      
      final names = {'000001': '上证指数', '399001': '深证成指', '399006': '创业板指', '000300': '沪深300'};
      
      for (final match in matches) {
        final parts = match.group(1)!.split('~');
        if (parts.length < 35) continue;
        
        final code = parts[2];
        result.add(MarketIndex(
          code: code,
          name: names[code] ?? parts[1],
          current: double.tryParse(parts[3]) ?? 0,
          change: double.tryParse(parts[31]) ?? 0,
          changeRate: double.tryParse(parts[32]) ?? 0,
          volume: double.tryParse(parts[6]) ?? 0,
        ));
      }
      return result;
    } catch (e) {
      debugPrint('[API] fetchMarketIndices error: $e');
      return [];
    }
  }

  /// 获取基金排行榜
  Future<List<FundRankItem>> fetchFundRanking({
    String sortType = 'r',  // r=日涨幅, zzf=周涨幅, 1yzf=月涨幅, 6yzf=6月涨幅, 1nzf=年涨幅
    String order = 'desc',
    int pageSize = 20,
    String fundType = 'all', // all/gp(股票)/hh(混合)/zq(债券)/zs(指数)/qdii(QDII)
  }) async {
    // 映射内部 sortType 到 rankhandler API 的 sc 参数
    const sortMap = {
      'r': 'rzdf',
      'zzf': 'zzf',
      '1yzf': '1yzf',
      '3yzf': '3yzf',
      '6yzf': '6yzf',
      '1nzf': '1nzf',
    };
    final apiSort = sortMap[sortType] ?? sortType;
    try {
      // 天天基金排行 API
      final response = await _dio.get(
        'https://fund.eastmoney.com/data/rankhandler.aspx',
        queryParameters: {
          'op': 'ph',
          'dt': 'kf',
          'ft': fundType,
          'rs': '',
          'gs': '0',
          'sc': apiSort,
          'st': order,
          'sd': _getRankStartDate(),
          'ed': _getTodayStr(),
          'qdii': '',
          'tabSubtype': ',,,,,',
          'pi': '1',
          'pn': pageSize.toString(),
          'dx': '1',
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': 'https://fund.eastmoney.com/'},
        ),
      );
      
      final bytes = response.data as Uint8List;
      // 天天基金排行 API 返回 UTF-8 编码（Content-Type: charset=utf-8）
      final text = utf8.decode(bytes);
      
      // 解析返回的 JS 格式数据
      final match = RegExp(r'var rankData = ({[\s\S]*?});').firstMatch(text);
      if (match == null) return [];
      
      final jsObj = match.group(1)!;
      // 天天基金 API 返回 JS 格式（key 无引号），需加引号后才能 jsonDecode
      final jsonStr = jsObj.replaceAllMapped(
        RegExp(r'([{,])\s*(\w+)\s*:'),
        (m) => '${m.group(1)}"${m.group(2)}":',
      );
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final items = data['datas'] as List? ?? [];
      
      return items.map((item) {
        final parts = (item as String).split(',');
        return FundRankItem(
          code: parts[0],
          name: parts[1],
          type: fundType,  // parts[3]是日期，类型由调用方参数决定
          netValue: double.tryParse(parts[4]) ?? 0,
          dayChange: double.tryParse(parts[6]) ?? 0,   // 日增长率
          weekChange: double.tryParse(parts[7]) ?? 0,  // 近一周
          monthChange: double.tryParse(parts[8]) ?? 0, // 近一月
          threeMonthChange: double.tryParse(parts[9]) ?? 0,  // 近三月
          halfYearChange: double.tryParse(parts[10]) ?? 0,   // 近六月
          yearChange: double.tryParse(parts[11]) ?? 0, // 近一年
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchFundRanking error: $e');
      return [];
    }
  }

  /// 搜索基金
  Future<List<FundInfo>> searchFund(String keyword, {int limit = 50, CancelToken? cancelToken}) async {
    if (keyword.isEmpty) return [];
    
    try {
      final response = await _dio.get(
        'https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx',
        queryParameters: {
          'm': '1',
          'cb': '',
          'key': keyword,
          'pagesize': limit.toString(),
        },
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      );
      
      final bytes = response.data as Uint8List;
      // fundsuggest.eastmoney.com 返回 UTF-8 编码，不是 GBK
      final text = utf8.decode(bytes);
      
      // 尝试解析 JSON（可能被 JSONP 包裹）
      String jsonStr = text.trim();
      if (jsonStr.startsWith('(') && jsonStr.endsWith(')')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
      }
      
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      // 检查 API 业务错误码
      final errCode = data['ErrCode'] as int? ?? 0;
      if (errCode != 0) {
        throw Exception('搜索API返回错误: ErrCode=$errCode, ErrMsg=${data['ErrMsg'] ?? 'unknown'}');
      }
      final items = data['Datas'] as List? ?? [];
      
      return items.map((item) {
        final map = item as Map<String, dynamic>;
        return FundInfo(
          code: (map['CODE'] ?? map['code'] ?? '').toString(),
          name: (map['NAME'] ?? map['name'] ?? '').toString(),
          type: (map['FUNDTYPE'] ?? map['type'] ?? '').toString(),
          pinyin: (map['JIANPIN'] ?? map['pinyin'] ?? '').toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[searchFund] 搜索 "$keyword" 失败: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 基金搜索与列表
  // ═══════════════════════════════════════════════════════════════

  /// 获取基金列表（热门）
  Future<List<FundInfo>> fetchFundList() async {
    // 返回一些热门基金
    return [
      FundInfo(code: '000001', name: '华夏成长混合', type: '混合型', pinyin: 'hxcz'),
      FundInfo(code: '110011', name: '易方达中小盘混合', type: '混合型', pinyin: 'yfdzxp'),
      FundInfo(code: '161725', name: '招商中证白酒指数', type: '指数型', pinyin: 'zszzbj'),
      FundInfo(code: '005827', name: '易方达蓝筹精选混合', type: '混合型', pinyin: 'yfdlcjx'),
      FundInfo(code: '012348', name: '天弘恒生科技指数(QDII)C', type: 'QDII', pinyin: 'thhskj'),
    ];
  }

  /// 获取基金详情信息（备用）
  Future<FundAccurateData?> fetchFundDetailInfo(String code) async {
    try {
      return await fetchFundAccurateData(code);
    } catch (e) {
      debugPrint('[API] fetchFundDetailInfo error ($code): $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 财经新闻
  // ══════════════════════════════════════════════════════════════════════

  /// 获取财经新闻（东方财富快讯）
  /// category: 101=全球, 102=快讯, 103=股票, 104=基金, 105=商品
  Future<List<NewsItem>> fetchFinanceNews({int pageSize = 10, String category = '102'}) async {
    try {
      final response = await _dio.get(
        'https://newsapi.eastmoney.com/kuaixun/v1/getlist_${category}_ajaxResult_${pageSize}_1_.html',
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': 'Mozilla/5.0'},
        ),
      );

      // 返回格式：var ajaxResult={...JSON...};
      final raw = response.data.toString();
      final jsonStart = raw.indexOf('{');
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd <= jsonStart) {
        debugPrint('[API] fetchFinanceNews: 无法解析 JSONP 响应');
        return [];
      }

      final data = jsonDecode(raw.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>;
      final newsList = data['LivesList'] as List? ?? [];

      return newsList.map((news) {
        final map = news as Map<String, dynamic>;
        return NewsItem(
          id: (map['id'] ?? '').toString(),
          title: (map['title'] ?? '').toString(),
          url: (map['url_w'] ?? '').toString(),
          time: (map['showtime'] ?? '').toString(),
          source: '东方财富',
          digest: (map['digest'] ?? '').toString(),
          imageUrl: (map['image'] ?? '').toString(),
          category: category,
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchFinanceNews error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 板块行情（排行 / 成分股 / 关联基金 / 板块诊断）
  // ═══════════════════════════════════════════════════════════════

  /// push2 系列域名回退请求（东方财富多 IP 屏蔽频繁，自动切换）
  static const _push2Hosts = [
    'push2his.eastmoney.com',
    'push2delay.eastmoney.com',
    'push2.eastmoney.com',
  ];

  Future<Response<dynamic>> _push2Get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    Object? lastError;
    for (final host in _push2Hosts) {
      try {
        return await _dio.get(
          'https://$host$path',
          queryParameters: queryParameters,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
      } catch (e) {
        lastError = e;
        debugPrint('[push2] $host failed, try next...');
      }
    }
    throw lastError!;
  }

  /// 获取热门板块排行（东方财富板块行情 API）
  Future<List<SectorRankItem>> fetchSectorRanking({int pageSize = 10}) async {
    try {
      final response = await _push2Get('/api/qt/clist/get', queryParameters: {
        'pn': '1',
        'pz': pageSize.toString(),
        'po': '1',
        'np': '1',
        'fltt': '2',
        'invt': '2',
        'fid': 'f3',
        'fs': 'm:90+t:2',
        'fields': 'f2,f3,f4,f12,f14',
      });

      final rawData2 = response.data;
      debugPrint('[API] fetchSectorRanking rawData type: ${rawData2.runtimeType}');
      if (rawData2 is String) {
        debugPrint('[API] fetchSectorRanking is String! first 100: ${rawData2.substring(0, rawData2.length > 100 ? 100 : rawData2.length)}');
      }
      final bytes = rawData2 is Uint8List ? rawData2 : Uint8List.fromList((rawData2 as String).codeUnits);
      final text = utf8.decode(bytes);
      debugPrint('[API] fetchSectorRanking decoded first 200: ${text.substring(0, text.length > 200 ? 200 : text.length)}');
      final data = jsonDecode(text) as Map<String, dynamic>;
      final diff = (data['data'] as Map<String, dynamic>?)?['diff'] as List? ?? [];

      return diff.map((item) {
        final map = item as Map<String, dynamic>;
        return SectorRankItem(
          code: (map['f12'] ?? '').toString(),
          name: (map['f14'] ?? '').toString(),
          price: double.tryParse(map['f2']?.toString() ?? '') ?? 0,
          changePercent: double.tryParse(map['f3']?.toString() ?? '') ?? 0,
          change: double.tryParse(map['f4']?.toString() ?? '') ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchSectorRanking error: $e');
      return [];
    }
  }

  /// 获取板块成分股列表
  Future<List<SectorConstituentItem>> fetchSectorConstituents(String sectorCode, {int pageSize = 50}) async {
    try {
      final response = await _push2Get('/api/qt/clist/get', queryParameters: {
        'pn': '1',
        'pz': pageSize.toString(),
        'po': '1',
        'np': '1',
        'fltt': '2',
        'invt': '2',
        'fid': 'f3',
        'fs': 'b:$sectorCode',
        'fields': 'f2,f3,f4,f8,f12,f14,f20',
      });

      final rawData = response.data;
      debugPrint('[API] fetchSectorConstituents rawData type: ${rawData.runtimeType}');
      if (rawData is Uint8List) {
        debugPrint('[API] fetchSectorConstituents first 20 bytes: ${rawData.sublist(0, rawData.length > 20 ? 20 : rawData.length)}');
      } else if (rawData is String) {
        debugPrint('[API] fetchSectorConstituents is String! first 100 chars: ${rawData.substring(0, rawData.length > 100 ? 100 : rawData.length)}');
      }
      final bytes = rawData is Uint8List ? rawData : Uint8List.fromList((rawData as String).codeUnits);
      final text = utf8.decode(bytes);
      debugPrint('[API] fetchSectorConstituents decoded first 200 chars: ${text.substring(0, text.length > 200 ? 200 : text.length)}');
      final data = jsonDecode(text) as Map<String, dynamic>;
      final diff = (data['data'] as Map<String, dynamic>?)?['diff'] as List? ?? [];

      return diff.map((item) {
        final map = item as Map<String, dynamic>;
        return SectorConstituentItem(
          code: (map['f12'] ?? '').toString(),
          name: (map['f14'] ?? '').toString(),
          price: double.tryParse(map['f2']?.toString() ?? '') ?? 0,
          changePercent: double.tryParse(map['f3']?.toString() ?? '') ?? 0,
          change: double.tryParse(map['f4']?.toString() ?? '') ?? 0,
          turnoverRate: double.tryParse(map['f8']?.toString() ?? ''),
          marketCap: (double.tryParse(map['f20']?.toString() ?? '')) != null
              ? (double.parse(map['f20'].toString()) / 1e8) // 转为亿
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchSectorConstituents error: $e');
      return [];
    }
  }

  /// 获取板块关联基金列表
  /// 用板块名称搜索基金，再批量获取估值涨跌
  Future<List<SectorFundItem>> fetchSectorFunds(String sectorName, {int pageSize = 20}) async {
    try {
      // Step 1: 直接调 fundsuggest API，提取 FundBaseInfo 中的 FTYPE/JJGS
      final response = await _dio.get(
        'https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx',
        queryParameters: {
          'm': '1',
          'cb': '',
          'key': sectorName,
          'pagesize': pageSize.toString(),
        },
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data as Uint8List;
      final text = utf8.decode(bytes);
      String jsonStr = text.trim();
      if (jsonStr.startsWith('(') && jsonStr.endsWith(')')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final errCode = data['ErrCode'] as int? ?? 0;
      if (errCode != 0) return [];
      final items = data['Datas'] as List? ?? [];
      if (items.isEmpty) return [];

      // 提取基金代码、名称、类型、公司
      final fundMeta = <String, _FundMeta>{};
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final code = (map['CODE'] ?? '').toString();
        final name = (map['NAME'] ?? '').toString();
        if (code.isEmpty || name.isEmpty) continue;

        final baseInfo = map['FundBaseInfo'] as Map<String, dynamic>?;
        fundMeta[code] = _FundMeta(
          code: code,
          name: name,
          type: (baseInfo?['FTYPE'] ?? '').toString(),
          company: (baseInfo?['JJGS'] ?? '').toString(),
        );
      }

      if (fundMeta.isEmpty) return [];

      // Step 2: 批量获取估值涨跌
      final codes = fundMeta.keys.toList();
      final estimates = await fetchFundEstimates(codes);

      // Step 3: 合并数据，有估值数据优先
      final funds = fundMeta.values.map((meta) {
        final est = estimates[meta.code];
        final hasValidEst = est != null && est.dwjz > 0;
        return SectorFundItem(
          code: meta.code,
          name: meta.name,
          type: meta.type,
          fundCompany: meta.company,
          netValue: hasValidEst ? est.dwjz : 0.0,
          estimateChange: hasValidEst ? est.gszzl : 0.0,
          estimateTime: hasValidEst ? est.gztime : '',
          hasEstimate: hasValidEst,
        );
      }).toList();

      // 排序：有估值数据的按涨跌幅降序，无估值的排后面
      funds.sort((a, b) {
        if (a.hasEstimate && !b.hasEstimate) return -1;
        if (!a.hasEstimate && b.hasEstimate) return 1;
        return b.estimateChange.compareTo(a.estimateChange);
      });

      return funds;
    } catch (e) {
      debugPrint('[API] fetchSectorFunds error: $e');
      return [];
    }
  }

  /// 通过基金名称识别板块名称（纯 Dart 关键词匹配）
  String identifySectorFromFundName(String fundName, String fundType, String fundCode) {
    final name = fundName.toLowerCase();
    final type = fundType.toLowerCase();
    final combined = '$name $type';

    // 关键词 → 板块名称
    final sectorMap = [
      // 科技类
      {'k': ['半导体', '芯片', '集成电路'], 's': '半导体'},
      {'k': ['人工智能', '机器人'], 's': '人工智能'},
      {'k': ['计算机', '软件', '云计算', '大数据'], 's': '计算机软件'},
      {'k': ['电子', '消费电子'], 's': '电子'},
      {'k': ['通信', '5g', '物联网'], 's': '通信'},
      {'k': ['新能源', '光伏', '风电', '电池', '储能'], 's': '新能源'},
      // 消费类
      {'k': ['白酒', '酒类'], 's': '白酒'},
      {'k': ['食品', '消费', '饮料'], 's': '食品饮料'},
      {'k': ['家电', '电器'], 's': '家电'},
      {'k': ['旅游', '酒店'], 's': '旅游酒店'},
      // 医药类
      {'k': ['医药', '医疗', '生物', '健康'], 's': '医药'},
      // 金融类
      {'k': ['银行'], 's': '银行'},
      {'k': ['证券', '券商'], 's': '证券'},
      {'k': ['保险'], 's': '保险'},
      {'k': ['金融'], 's': '金融'},
      // 周期类
      {'k': ['钢铁'], 's': '钢铁'},
      {'k': ['煤炭'], 's': '煤炭'},
      {'k': ['有色', '黄金', '稀土'], 's': '有色金属'},
      {'k': ['化工'], 's': '化工'},
      {'k': ['房地产', '地产'], 's': '房地产'},
      {'k': ['军工', '国防'], 's': '军工'},
      // 海外
      {'k': ['恒生', '港股', '沪港深'], 's': '港股'},
      {'k': ['纳斯达克', '标普', '美国', '美股'], 's': '美股'},
      {'k': ['日本', '印度', '欧洲', '德国'], 's': '海外'},
      // 市场类型
      {'k': ['蓝筹', '大盘', '价值'], 's': '大盘'},
      {'k': ['中小盘', '成长'], 's': '中小盘'},
      {'k': ['创业板', '科创', '创新'], 's': '创业板'},
      {'k': ['红利', '分红', '价值'], 's': '红利'},
    ];

    for (final entry in sectorMap) {
      final keywords = entry['k'] as List<String>;
      final sector = entry['s'] as String;
      if (keywords.any((kw) => combined.contains(kw.toLowerCase()))) {
        return sector;
      }
    }

    // 代码前缀判断
    final prefix = fundCode.length >= 3 ? fundCode.substring(0, 3) : fundCode;
    final codeSectorMap = {
      '510': '上交所ETF', '511': '货币ETF', '512': '上交所ETF',
      '513': '港股ETF', '515': '上交所ETF', '518': '黄金ETF',
      '159': '深交所ETF',
      '000': '沪深主板', '001': '沪深主板', '002': '中小板',
      '010': '创业板', '011': '创业板', '012': '创业板',
      '013': '科创板', '014': '科创板', '015': '科创板',
      '016': '混合基金', '017': '混合基金', '018': '混合基金',
      '110': '混合/股票', '161': 'LOF基金', '164': 'LOF基金',
    };
    if (codeSectorMap.containsKey(prefix)) {
      return codeSectorMap[prefix]!;
    }

    // 基金类型兜底
    if (type.contains('股票')) return '股票型';
    if (type.contains('混合')) return '混合型';
    if (type.contains('债券')) return '债券型';
    if (type.contains('货币')) return '货币型';
    if (type.contains('指数')) return '指数型';
    if (type.contains('qdii')) return '海外';
    if (type.contains('FOF')) return 'FOF';

    return '综合/混合';
  }

  /// 从东方财富获取热门板块行情（今日涨跌幅）
  /// f3=涨跌幅, f12=板块代码, f14=板块名称
  Future<SectorInfo?> fetchSectorInfo(String fundName, String fundType, String fundCode) async {
    try {
      final sectorName = identifySectorFromFundName(fundName, fundType, fundCode);
      debugPrint('[SectorInfo] identified sector: $sectorName for $fundName');

      // 获取行业板块列表（push2 系列域名自动回退）
      final resp = await _push2Get('/api/qt/clist/get', queryParameters: {
        'pn': '1',
        'pz': '50',
        'po': '1',
        'np': '1',
        'fltt': '2',
        'invt': '2',
        'fid': 'f3',
        'fs': 'm:90+t:2',
        'fields': 'f2,f3,f12,f14,f104,f105',
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final respBytes = resp.data as Uint8List;
      final respText = utf8.decode(respBytes);
      final data = jsonDecode(respText) as Map<String, dynamic>?;
      final diff = data?['data']?['diff'] as List? ?? [];

      // 匹配板块名称
      SectorInfo? matched;
      for (final item in diff) {
        final m = item as Map<String, dynamic>;
        final name = (m['f14'] ?? '').toString();
        if (name.contains(sectorName) || sectorName.contains(name)) {
          final dayReturn = double.tryParse((m['f3'] ?? '0').toString()) ?? 0.0;
          final upCount = int.tryParse((m['f104'] ?? '0').toString()) ?? 0;
          final downCount = int.tryParse((m['f105'] ?? '0').toString()) ?? 0;
          String streak;
          if (dayReturn > 3) {
            streak = '大涨';
          } else if (dayReturn > 0) {
            streak = '涨 $upCount只';
          } else if (dayReturn < -3) {
            streak = '大跌';
          } else if (dayReturn < 0) {
            streak = '跌 $downCount只';
          } else {
            streak = '平';
          }
          matched = SectorInfo(
            code: (m['f12'] ?? '').toString(),
            name: name,
            dayReturn: dayReturn,
            streak: streak,
          );
          debugPrint('[SectorInfo] matched: $name, return=$dayReturn%');
          break;
        }
      }

      // 如果没匹配到，返回纯名称+0
      if (matched == null) {
        debugPrint('[SectorInfo] no market data for sector: $sectorName');
        matched = SectorInfo(
          code: '',
          name: sectorName,
          dayReturn: 0.0,
          streak: fundType,
        );
      }

      return matched;
    } catch (e) {
      debugPrint('[SectorInfo] error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 辅助方法
  // ══════════════════════════════════════════════════════════════════════

  String _getTodayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _getRankStartDate() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    return '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }

  /// 清除所有缓存
  void clearCache() {
    _pzCache.clear();
    _gzCache.clear();
    _djCache.clear();
    debugPrint('[API] 所有缓存已清除');
  }

  // ══════════════════════════════════════════════════════════════════════
  // 蛋卷基金 API（雪球旗下，数据质量极高）
  // ══════════════════════════════════════════════════════════════════════

  /// 蛋卷基金缓存（24h TTL）
  final Map<String, _DjData> _djCache = {};

  /// 获取蛋卷基金详情（含持仓/行业/资产/费率）
  /// API: https://danjuanfunds.com/djapi/fund/detail/{code}
  /// 无需鉴权，返回 JSON
  Future<_DjData?> _fetchDjData(String code) async {
    // 缓存检查（24h）
    final cached = _djCache[code];
    if (cached != null && DateTime.now().millisecondsSinceEpoch - cached.fetchedAt < 86400000) {
      return cached;
    }

    try {
      final response = await _dio.get(
        'https://danjuanfunds.com/djapi/fund/detail/$code',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
            'Referer': 'https://danjuanfunds.com/',
          },
        ),
      );

      final text = response.data as String;
      final json = jsonDecode(text) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;

      if (data == null) {
        debugPrint('[DjData] no data for $code');
        return null;
      }

      final result = _DjData.fromJson(data, code);
      _djCache[code] = result;

      debugPrint('[DjData] loaded $code: '
          'stocks=${result.stockList.length}, '
          'industries=${result.industryList.length}, '
          'asset=${result.stockPercent}%/${result.cashPercent}%');

      return result;
    } catch (e) {
      debugPrint('[DjData] error for $code: $e');
      return null;
    }
  }

  /// 通过蛋卷 API 获取重仓股（含行业标签、实时行情、较上期变动）
  Future<List<StockHolding>> fetchStockHoldingsWithInfo(String code) async {
    // 优先蛋卷
    final dj = await _fetchDjData(code);
    if (dj != null && dj.stockList.isNotEmpty) {
      return dj.stockList;
    }

    // 降级：东方财富 HTML
    debugPrint('[StockHoldings] danjuan empty, fallback to eastmoney HTML');
    try {
      final html = await _fetchStockHoldingsHtml(code);
      if (html == null || html.isEmpty) return [];

      final holdings = _parseStockHoldingsHtml(html);
      if (holdings.isEmpty) return [];

      final stockCodes = holdings.map((h) => h.stockCode).toList();
      final quotes = await fetchStockQuotesBatch(stockCodes);

      return holdings.map((h) {
        final quote = quotes[h.stockCode];
        return StockHolding(
          stockCode: h.stockCode,
          stockName: quote?['name'] ?? h.stockName,
          holdingRatio: h.holdingRatio,
          holdingAmount: h.holdingAmount,
          changeFromLast: '${quote?['changePercent'] ?? 0.0}%',
        );
      }).toList();
    } catch (e) {
      debugPrint('[StockHoldings] fallback error: $e');
      return [];
    }
  }

  /// 通过蛋卷 API 获取行业配置（已聚合好的行业分布）
  Future<List<IndustryAllocation>> fetchIndustryAllocation(String code) async {
    // 优先蛋卷
    final dj = await _fetchDjData(code);
    if (dj != null && dj.industryList.isNotEmpty) {
      return dj.industryList;
    }

    // 降级：pingzhongdata
    debugPrint('[IndustryAllocation] danjuan empty, fallback to pingzhongdata');
    try {
      final pz = await _fetchPzData(code);
      return pz.industryItems.map((item) {
        final map = item as Map<String, dynamic>;
        return IndustryAllocation(
          name: (map['name'] ?? '').toString(),
          industry: (map['name'] ?? '').toString(),
          percent: (map['y'] ?? 0).toDouble(),
          proportion: (map['y'] ?? 0).toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[IndustryAllocation] fallback error: $e');
      return [];
    }
  }

  /// 通过蛋卷 API 获取资产配置
  Future<AssetAllocation?> fetchAssetAllocation(String code) async {
    // 优先蛋卷
    final dj = await _fetchDjData(code);
    if (dj != null) {
      return AssetAllocation(
        stocks: dj.stockPercent,
        bonds: 0.0, // 蛋卷 chart_list 不含债券
        cash: dj.cashPercent,
        others: dj.otherPercent,
      );
    }

    // 降级：pingzhongdata
    debugPrint('[AssetAllocation] danjuan empty, fallback to pingzhongdata');
    try {
      final pz = await _fetchPzData(code);
      if (pz.assetSeries.isEmpty) return null;

      double stocks = 0, bonds = 0, cash = 0, others = 0;
      for (final item in pz.assetSeries) {
        final map = item as Map<String, dynamic>;
        final name = (map['name'] ?? '').toString();
        if (map['data'] is List && (map['data'] as List).isNotEmpty) {
          final data = map['data'] as List;
          final latestValue = (data.last as num?)?.toDouble() ?? 0.0;
          if (name.contains('股票')) {
            stocks = latestValue;
          } else if (name.contains('债券')) {
            bonds = latestValue;
          } else if (name.contains('现金')) {
            cash = latestValue;
          } else if (name.contains('其他')) {
            others = latestValue;
          }
        }
      }
      return AssetAllocation(stocks: stocks, bonds: bonds, cash: cash, others: others);
    } catch (e) {
      debugPrint('[API] fetchAssetAllocation error ($code): $e');
      return null;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// pingzhongdata 解析结果内部类
// ══════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════
// 内部辅助类
// ══════════════════════════════════════════════════════════════════════

/// 重仓股解析中间结果
class _StockRaw {
  final String stockCode;
  final String stockName;
  final double holdingRatio;
  final String holdingAmount;
  final String changeFromLast;

  _StockRaw({
    required this.stockCode,
    required this.stockName,
    required this.holdingRatio,
    required this.holdingAmount,
    required this.changeFromLast,
  });
}

/// 板块基金搜索辅助类
class _FundMeta {
  final String code;
  final String name;
  final String type;
  final String company;

  const _FundMeta({
    required this.code,
    required this.name,
    this.type = '',
    this.company = '',
  });
}

/// pingzhongdata 解析结果
class _PzData {
  String? fSName;
  String? fSCode;
  double? fundSourceRate;
  double? fundRate;
  double? fundMinsg;
  double? syl1n;
  double? syl6y;
  double? syl3y;
  double? syl1y;
  
  List<dynamic> managers = [];
  List<dynamic> stocks = [];
  List<dynamic> netWorthTrend = [];
  List<dynamic> millionCopiesIncome = []; // 货币基金：每万份收益 Data_millionCopiesIncome
  List<dynamic> fluctuationScale = [];
  List<String> stockCodes = [];

  // 行业配置：Data_IndustryAllocation 格式 { series: [{ data: [{name, y}] }] }
  List<dynamic> industryItems = [];

  // 资产配置：Data_assetAllocation 格式 { series: [{name, data:[...]}] }
  List<dynamic> assetSeries = [];
}

/// 蛋卷基金 API 解析结果
class _DjData {
  final int fetchedAt;
  final String code;
  final String sourceMark; // "年报" / "季报"
  final String endDate;    // "2025-12-31"

  // 资产配置
  final double stockPercent;
  final double cashPercent;
  final double otherPercent;

  // 重仓股列表（已转为 StockHolding）
  final List<StockHolding> stockList;

  // 行业分布（已转为 IndustryAllocation）
  final List<IndustryAllocation> industryList;

  _DjData({
    required this.fetchedAt,
    required this.code,
    required this.sourceMark,
    required this.endDate,
    required this.stockPercent,
    required this.cashPercent,
    required this.otherPercent,
    required this.stockList,
    required this.industryList,
  });

  factory _DjData.fromJson(Map<String, dynamic> data, String code) {
    final position = data['fund_position'] as Map<String, dynamic>? ?? {};

    // 资产配置
    final stockPct = (position['stock_percent'] as num?)?.toDouble() ?? 0.0;
    final cashPct = (position['cash_percent'] as num?)?.toDouble() ?? 0.0;
    final otherPct = (position['other_percent'] as num?)?.toDouble() ?? 0.0;

    // 重仓股
    final stockRaw = position['stock_list'] as List? ?? [];
    final stocks = stockRaw.map((item) {
      final m = item as Map<String, dynamic>;
      return StockHolding(
        stockCode: (m['code'] ?? '').toString(),
        stockName: (m['name'] ?? '').toString(),
        holdingRatio: (m['percent'] as num?)?.toDouble() ?? 0.0,
        holdingAmount: '', // 蛋卷不提供持股数/市值
        changeFromLast: (m['change_of_pre_quarter'] ?? '--').toString(),
        currentPrice: (m['current_price'] as num?)?.toDouble(),
        changePercent: (m['change_percentage'] as num?)?.toDouble(),
        industryLabel: m['industry_label'] as String?,
        isAMarket: m['amarket'] as bool? ?? true,
        changeOfPreQuarter: m['change_of_pre_quarter'] as String?,
      );
    }).toList();

    // 行业分布
    final industryRaw = position['industry_list'] as List? ?? [];
    final industries = industryRaw.map((item) {
      final m = item as Map<String, dynamic>;
      return IndustryAllocation(
        name: (m['industry_name'] ?? '').toString(),
        industryCode: m['industry_code'] as String?,
        percent: (m['percent'] as num?)?.toDouble() ?? 0.0,
        color: m['color'] as String?,
      );
    }).toList();

    // 如果行业分布为空但有重仓股带 industry_label，从重仓股反推
    if (industries.isEmpty && stocks.isNotEmpty) {
      final Map<String, double> labelMap = {};
      for (final s in stocks) {
        if (s.industryLabel != null && s.industryLabel!.isNotEmpty) {
          labelMap[s.industryLabel!] = (labelMap[s.industryLabel!] ?? 0) + s.holdingRatio;
        }
      }
      // 按占比排序
      final sorted = labelMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      industries.addAll(sorted.map((e) => IndustryAllocation(
        name: e.key,
        industryCode: null,
        percent: double.parse(e.value.toStringAsFixed(2)),
        color: null,
      )));
      debugPrint('[DjData] inferred ${industries.length} industries from stock labels');
    }

    return _DjData(
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      code: code,
      sourceMark: (position['source_mark'] ?? '').toString(),
      endDate: (position['end_date_str'] ?? '').toString(),
      stockPercent: stockPct,
      cashPercent: cashPct,
      otherPercent: otherPct,
      stockList: stocks,
      industryList: industries,
    );
  }
}
