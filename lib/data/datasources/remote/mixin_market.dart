import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gbk_codec/gbk_codec.dart' as gbk_pkg;
import '../../../domain/entities/fund_entity.dart';
import 'remote_dio_accessor.dart';

/// 市场数据 mixin
/// 职责：大盘指数、基金排行榜、基金搜索、财经新闻
mixin MarketDataSource on RemoteDioAccessor {
  /// 获取大盘指数
  Future<List<MarketIndex>> fetchMarketIndices() async {
    try {
      final codes = ['sh000001', 'sz399001', 'sz399006', 'sh000300'];
      final response = await dio.get('https://qt.gtimg.cn/q=${codes.join(',')}',
          options: Options(responseType: ResponseType.bytes));
      final text = gbk_pkg.gbk.decode(response.data as Uint8List);

      final result = <MarketIndex>[];
      final matches = RegExp(r'"(.*?)"').allMatches(text);
      final names = {
        '000001': '上证指数',
        '399001': '深证成指',
        '399006': '创业板指',
        '000300': '沪深300'
      };

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
    String sortType = 'r',
    String order = 'desc',
    int pageSize = 20,
    String fundType = 'all',
  }) async {
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
      final response = await dio.get(
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
      final text = utf8.decode(bytes);

      final match = RegExp(r'var rankData = ({[\s\S]*?});').firstMatch(text);
      if (match == null) return [];

      final jsObj = match.group(1)!;
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
          type: fundType,
          netValue: double.tryParse(parts[4]) ?? 0,
          dayChange: double.tryParse(parts[6]) ?? 0,
          weekChange: double.tryParse(parts[7]) ?? 0,
          monthChange: double.tryParse(parts[8]) ?? 0,
          threeMonthChange: double.tryParse(parts[9]) ?? 0,
          halfYearChange: double.tryParse(parts[10]) ?? 0,
          yearChange: double.tryParse(parts[11]) ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchFundRanking error: $e');
      return [];
    }
  }

  /// 搜索基金
  Future<List<FundInfo>> searchFund(String keyword,
      {int limit = 50, CancelToken? cancelToken}) async {
    if (keyword.isEmpty) return [];
    try {
      final response = await dio.get(
        'https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx',
        queryParameters: {
          'm': '1',
          'cb': '',
          'key': keyword,
          'pagesize': limit.toString()
        },
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      );
      final bytes = response.data as Uint8List;
      final text = utf8.decode(bytes);

      String jsonStr = text.trim();
      if (jsonStr.startsWith('(') && jsonStr.endsWith(')')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
      }
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final errCode = data['ErrCode'] as int? ?? 0;
      if (errCode != 0) {
        throw Exception(
            '搜索API返回错误: ErrCode=$errCode, ErrMsg=${data['ErrMsg'] ?? 'unknown'}');
      }
      final items = data['Datas'] as List? ?? [];
      return items
          .where(
              (item) => (item as Map<String, dynamic>)['CATEGORYDESC'] == '基金')
          .map((item) {
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

  /// 获取基金列表（热门）
  Future<List<FundInfo>> fetchFundList() async {
    return [
      FundInfo(code: '000001', name: '华夏成长混合', type: '混合型', pinyin: 'hxcz'),
      FundInfo(code: '110011', name: '易方达中小盘混合', type: '混合型', pinyin: 'yfdzxp'),
      FundInfo(code: '161725', name: '招商中证白酒指数', type: '指数型', pinyin: 'zszzbj'),
      FundInfo(
          code: '005827', name: '易方达蓝筹精选混合', type: '混合型', pinyin: 'yfdlcjx'),
      FundInfo(
          code: '012348',
          name: '天弘恒生科技指数(QDII)C',
          type: 'QDII',
          pinyin: 'thhskj'),
    ];
  }

  /// 获取财经新闻
  Future<List<NewsItem>> fetchFinanceNews(
      {int pageSize = 10, String category = '102'}) async {
    try {
      final response = await dio.get(
        'https://newsapi.eastmoney.com/kuaixun/v1/getlist_${category}_ajaxResult_${pageSize}_1_.html',
        options: Options(
            responseType: ResponseType.plain,
            headers: {'User-Agent': 'Mozilla/5.0'}),
      );
      final raw = response.data.toString();
      final jsonStart = raw.indexOf('{');
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd <= jsonStart) return [];

      final data = jsonDecode(raw.substring(jsonStart, jsonEnd + 1))
          as Map<String, dynamic>;
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

  // ── 辅助 ──

  String _getTodayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _getRankStartDate() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    return '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }
}
