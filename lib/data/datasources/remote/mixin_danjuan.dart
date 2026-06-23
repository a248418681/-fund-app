import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gbk_codec/gbk_codec.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../utils/cache_manager.dart';
import 'internal_models.dart';
import 'remote_dio_accessor.dart';

/// 蛋卷基金 API mixin
/// 职责：蛋卷基金详情、重仓股、行业配置、资产配置（含东方财富 HTML 降级）
mixin DanjuanDataSource on RemoteDioAccessor {
  // ── 缓存 ──
  final CacheManager<DjData> _djCacheMgr =
      CacheManager(24 * 60 * 60 * 1000); // 24h

  /// 获取蛋卷基金详情
  Future<DjData?> fetchDjData(String code) async {
    final cached = _djCacheMgr.get(code);
    if (cached != null) return cached;

    try {
      final response = await dio.get(
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

      if (data == null) return null;

      final result = DjData.fromJson(data, code);
      _djCacheMgr.set(code, result);
      return result;
    } catch (e) {
      debugPrint('[DjData] error for $code: $e');
      return null;
    }
  }

  /// 通过蛋卷 API 获取重仓股（含行业标签、实时行情、较上期变动）
  Future<List<StockHolding>> fetchStockHoldingsWithInfo(String code) async {
    // 优先蛋卷
    final dj = await fetchDjData(code);
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

  /// 获取重仓股（兼容旧接口）
  Future<List<StockHolding>> fetchStockHoldings(String code) async {
    return fetchStockHoldingsWithInfo(code);
  }

  /// 获取行业配置
  Future<List<IndustryAllocation>> fetchIndustryAllocation(String code) async {
    final dj = await fetchDjData(code);
    if (dj != null && dj.industryList.isNotEmpty) {
      return dj.industryList;
    }

    // 降级：pingzhongdata（由 facade 中转，这里不直接调用）
    return [];
  }

  /// 获取资产配置
  Future<AssetAllocation?> fetchAssetAllocation(String code) async {
    final dj = await fetchDjData(code);
    if (dj != null) {
      return AssetAllocation(
        stocks: dj.stockPercent,
        bonds: 0.0,
        cash: dj.cashPercent,
        others: dj.otherPercent,
      );
    }
    return null;
  }

  // ── 东方财富 HTML 降级 ──

  Future<String?> _fetchStockHoldingsHtml(String code) async {
    try {
      final response = await dio.get(
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
            'User-Agent': 'Mozilla/5.0'
          },
        ),
      );

      var text = response.data.toString();
      final jsonpMatch =
          RegExp(r'''\(["'](.+?)["']\)''', dotAll: true).firstMatch(text);
      if (jsonpMatch != null) {
        text = jsonpMatch.group(1) ?? text;
      }
      return text;
    } catch (e) {
      debugPrint('[_fetchStockHoldingsHtml] error: $e');
      return null;
    }
  }

  List<StockRaw> _parseStockHoldingsHtml(String html) {
    final holdings = <StockRaw>[];
    final stockRegex =
        RegExp(r'//quote\.eastmoney\.com/unify/r/\d+\.(\d{5,6})');
    final bondRegex =
        RegExp(r'//quote\.eastmoney\.com/bond/(?:sh|sz)(\d{6})\.html');
    final pctRegex = RegExp(r'([\d\.]+)%');
    final numRegex = RegExp(r'([\d,\.]+)');

    final allMatches = <RegExpMatch>[];
    final matchTypes = <String>[];
    for (final m in stockRegex.allMatches(html)) {
      allMatches.add(m);
      matchTypes.add('stock');
    }
    for (final m in bondRegex.allMatches(html)) {
      allMatches.add(m);
      matchTypes.add('bond');
    }

    final indexed = allMatches.asMap().entries.toList()
      ..sort((a, b) => a.value.start.compareTo(b.value.start));
    final sortedMatches =
        indexed.map((e) => MapEntry(e.value, matchTypes[e.key])).toList();

    for (var i = 0; i < sortedMatches.length; i++) {
      final cm = sortedMatches[i].key;
      final assetType = sortedMatches[i].value;
      final stockCode = cm.group(1) ?? '';
      if (stockCode.isEmpty) continue;

      final start = cm.start;
      final window = html.substring(start, (start + 500).clamp(0, html.length));

      final pctMatch = pctRegex.firstMatch(window);
      if (pctMatch == null) continue;
      final ratio =
          double.tryParse(pctMatch.group(1)?.replaceAll(',', '') ?? '') ?? 0.0;

      final afterPct = window.substring(pctMatch.end);
      final numsInRow = numRegex.allMatches(afterPct).take(5).toList();
      String amount = '0';
      if (numsInRow.isNotEmpty) amount = numsInRow[0].group(1) ?? '0';

      final nameInLink = RegExp(r'\]\[([^[\]]{2,20})\]\(').firstMatch(window);
      final stockName = nameInLink?.group(1)?.trim() ??
          (assetType == 'bond' ? '债券$stockCode' : '股票$stockCode');

      final changeMatch = RegExp(r'([+\-][\d\.]+%)').firstMatch(afterPct);
      final change = changeMatch?.group(1) ?? '--';

      holdings.add(StockRaw(
        stockCode: stockCode,
        stockName: assetType == 'bond' ? '$stockName(债券)' : stockName,
        holdingRatio: ratio,
        holdingAmount: amount.replaceAll(',', ''),
        changeFromLast: change,
      ));
    }
    return holdings;
  }

  // ── 股票行情（腾讯 API）──

  Future<Map<String, dynamic>?> fetchStockQuote(String stockCode) async {
    try {
      String prefix =
          stockCode.startsWith('6') || stockCode.startsWith('68') ? 'sh' : 'sz';
      final response = await dio.get('https://qt.gtimg.cn/q=$prefix$stockCode',
          options: Options(responseType: ResponseType.bytes));
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

  Future<Map<String, Map<String, dynamic>>> fetchStockQuotesBatch(
      List<String> stockCodes) async {
    if (stockCodes.isEmpty) return {};
    try {
      final symbols = stockCodes.map((code) {
        String prefix =
            code.startsWith('6') || code.startsWith('68') ? 'sh' : 'sz';
        return '$prefix$code';
      }).join(',');

      final response = await dio.get('https://qt.gtimg.cn/q=$symbols',
          options: Options(responseType: ResponseType.bytes));
      final qBytes = response.data as Uint8List;
      final text = gbk.decode(qBytes);
      final result = <String, Map<String, dynamic>>{};

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

  /// DJ 缓存清理（供 facade 调用）
  void clearDjCache() => _djCacheMgr.clear();
}
