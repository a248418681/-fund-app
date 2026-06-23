import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../domain/entities/fund_entity.dart';
import 'internal_models.dart';
import 'remote_dio_accessor.dart';

/// 板块行情 mixin
/// 职责：板块排行、成分股、关联基金（关键词搜索 + 持仓穿透）、板块识别
/// 依赖：fetchFundEstimates（由 facade 提供）
mixin SectorDataSource on RemoteDioAccessor {
  /// 由 facade 提供（FundEstimateDataSource.fetchFundEstimates）
  Future<Map<String, FundEstimate>> fetchFundEstimates(List<String> codes);

  /// push2 系列域名回退请求
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
        return await dio.get(
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

  /// 获取热门板块排行
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

      final bytes = response.data is Uint8List
          ? response.data as Uint8List
          : Uint8List.fromList((response.data as String).codeUnits);
      final text = utf8.decode(bytes);
      final data = jsonDecode(text) as Map<String, dynamic>;
      final diff =
          (data['data'] as Map<String, dynamic>?)?['diff'] as List? ?? [];

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
  Future<List<SectorConstituentItem>> fetchSectorConstituents(String sectorCode,
      {int pageSize = 50}) async {
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

      final bytes = response.data is Uint8List
          ? response.data as Uint8List
          : Uint8List.fromList((response.data as String).codeUnits);
      final text = utf8.decode(bytes);
      final data = jsonDecode(text) as Map<String, dynamic>;
      final diff =
          (data['data'] as Map<String, dynamic>?)?['diff'] as List? ?? [];

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
              ? (double.parse(map['f20'].toString()) / 1e8)
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('[API] fetchSectorConstituents error: $e');
      return [];
    }
  }

  /// 获取板块关联基金
  Future<List<SectorFundItem>> fetchSectorFunds(String sectorName,
      {int pageSize = 20}) async {
    return _fetchSectorFundsWithFallback(sectorName, pageSize);
  }

  /// 概念→基金持仓管线
  Future<List<SectorFundItem>> fetchSectorFundsByHoldings(
    String sectorCode,
    String sectorName, {
    int pageSize = 30,
  }) async {
    try {
      final stocks = await fetchSectorConstituents(sectorCode, pageSize: 200);
      if (stocks.isEmpty) return [];

      final stockCodes = stocks.map((s) => s.code).toList();
      final allHolderLists =
          await _batchFetchStockHolders(stockCodes, concurrency: 15);

      final fundMap = <String, AggregatedFund>{};
      for (final holders in allHolderLists) {
        for (final h in holders) {
          final existing = fundMap[h.holderCode];
          if (existing == null) {
            fundMap[h.holderCode] = AggregatedFund(
              code: h.holderCode,
              name: h.holderName,
              parentOrgName: h.parentOrgName,
              totalHolding: h.holdingMarketCap,
              stockCount: 1,
              stocks: {h.stockCode},
            );
          } else {
            existing.totalHolding += h.holdingMarketCap;
            existing.stockCount++;
            existing.stocks.add(h.stockCode);
          }
        }
      }

      if (fundMap.isEmpty) return [];

      final sorted = fundMap.values.toList()
        ..sort((a, b) => b.totalHolding.compareTo(a.totalHolding));
      final topFunds = sorted.take(pageSize).toList();

      final codes = topFunds.map((f) => f.code).toList();
      final estimates = await fetchFundEstimates(codes);

      return topFunds.map((f) {
        final est = estimates[f.code];
        return SectorFundItem(
          code: f.code,
          name: f.name,
          type: _inferFundType(f.name),
          fundCompany: f.parentOrgName,
          netValue: est?.dwjz ?? 0,
          estimateChange: est?.gszzl ?? 0,
          estimateTime: est?.gztime ?? '',
          hasEstimate: est != null && est.gszzl != 0,
          holdingMarketCap: f.totalHolding,
          stockCount: f.stockCount,
        );
      }).toList();
    } catch (e) {
      debugPrint('[SectorFundHoldings] error: $e');
      return [];
    }
  }

  /// 板块识别：从基金名称推断板块
  String identifySectorFromFundName(
      String fundName, String fundType, String fundCode) {
    final name = fundName.toLowerCase();
    final type = fundType.toLowerCase();
    final combined = '$name $type';

    final sectorMap = [
      {
        'k': ['半导体', '芯片', '集成电路'],
        's': '半导体'
      },
      {
        'k': ['人工智能', '机器人'],
        's': '人工智能'
      },
      {
        'k': ['计算机', '软件', '云计算', '大数据'],
        's': '计算机软件'
      },
      {
        'k': ['电子', '消费电子'],
        's': '电子'
      },
      {
        'k': ['通信', '5g', '物联网'],
        's': '通信'
      },
      {
        'k': ['新能源', '光伏', '风电', '电池', '储能'],
        's': '新能源'
      },
      {
        'k': ['白酒', '酒类'],
        's': '白酒'
      },
      {
        'k': ['食品', '消费', '饮料'],
        's': '食品饮料'
      },
      {
        'k': ['家电', '电器'],
        's': '家电'
      },
      {
        'k': ['旅游', '酒店'],
        's': '旅游酒店'
      },
      {
        'k': ['医药', '医疗', '生物', '健康'],
        's': '医药'
      },
      {
        'k': ['银行'],
        's': '银行'
      },
      {
        'k': ['证券', '券商'],
        's': '证券'
      },
      {
        'k': ['保险'],
        's': '保险'
      },
      {
        'k': ['金融'],
        's': '金融'
      },
      {
        'k': ['钢铁'],
        's': '钢铁'
      },
      {
        'k': ['煤炭'],
        's': '煤炭'
      },
      {
        'k': ['有色', '黄金', '稀土'],
        's': '有色金属'
      },
      {
        'k': ['化工'],
        's': '化工'
      },
      {
        'k': ['房地产', '地产'],
        's': '房地产'
      },
      {
        'k': ['军工', '国防'],
        's': '军工'
      },
      {
        'k': ['恒生', '港股', '沪港深'],
        's': '港股'
      },
      {
        'k': ['纳斯达克', '标普', '美国', '美股'],
        's': '美股'
      },
      {
        'k': ['日本', '印度', '欧洲', '德国'],
        's': '海外'
      },
      {
        'k': ['蓝筹', '大盘', '价值'],
        's': '大盘'
      },
      {
        'k': ['中小盘', '成长'],
        's': '中小盘'
      },
      {
        'k': ['创业板', '科创', '创新'],
        's': '创业板'
      },
      {
        'k': ['红利', '分红', '价值'],
        's': '红利'
      },
    ];

    for (final entry in sectorMap) {
      final keywords = entry['k'] as List<String>;
      final sector = entry['s'] as String;
      if (keywords.any((kw) => combined.contains(kw.toLowerCase()))) {
        return sector;
      }
    }

    final prefix = fundCode.length >= 3 ? fundCode.substring(0, 3) : fundCode;
    final codeSectorMap = {
      '510': '上交所ETF',
      '511': '货币ETF',
      '512': '上交所ETF',
      '513': '港股ETF',
      '515': '上交所ETF',
      '518': '黄金ETF',
      '159': '深交所ETF',
      '000': '沪深主板',
      '001': '沪深主板',
      '002': '中小板',
      '010': '创业板',
      '011': '创业板',
      '012': '创业板',
      '013': '科创板',
      '014': '科创板',
      '015': '科创板',
      '016': '混合基金',
      '017': '混合基金',
      '018': '混合基金',
      '110': '混合/股票',
      '161': 'LOF基金',
      '164': 'LOF基金',
    };
    if (codeSectorMap.containsKey(prefix)) return codeSectorMap[prefix]!;

    if (type.contains('股票')) return '股票型';
    if (type.contains('混合')) return '混合型';
    if (type.contains('债券')) return '债券型';
    if (type.contains('货币')) return '货币型';
    if (type.contains('指数')) return '指数型';
    if (type.contains('qdii')) return '海外';
    if (type.contains('FOF')) return 'FOF';
    return '综合/混合';
  }

  /// 获取板块信息
  Future<SectorInfo?> fetchSectorInfo(
      String fundName, String fundType, String fundCode) async {
    try {
      final sectorName =
          identifySectorFromFundName(fundName, fundType, fundCode);

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
          return SectorInfo(
            code: (m['f12'] ?? '').toString(),
            name: name,
            dayReturn: dayReturn,
            streak: streak,
          );
        }
      }

      return SectorInfo(
          code: '', name: sectorName, dayReturn: 0.0, streak: fundType);
    } catch (e) {
      debugPrint('[SectorInfo] error: $e');
      return null;
    }
  }

  // ── 内部方法 ──

  static const Map<String, List<String>> _conceptRelatedKeywords = {
    '机器人': ['高端制造'],
    '人工智能': ['计算机'],
    '半导体': ['芯片'],
    '新能源': ['光伏'],
    '新能源汽车': ['汽车'],
    '军工': ['国防'],
    '医药': ['医疗'],
    '消费': ['食品饮料'],
    '数字经济': ['大数据'],
    '光伏': ['新能源'],
    '锂电池': ['新能源'],
    '储能': ['新能源'],
    '低空经济': ['无人机'],
  };

  String _extractSectorKeyword(String sectorName) {
    const suffixes = [
      '设备',
      '服务',
      '制造',
      '材料',
      '能源',
      '板块',
      '行业',
      '技术',
      '整车',
      '机械',
      '制品',
      '元件',
      '工程',
      '运营',
      '开发',
      '金融',
      '食品',
      '饮料',
      '旅游',
      '酒店',
      '钢铁',
      '银行',
      '证券',
      '保险',
      '地产',
      '军工',
      '国防',
      '汽车',
      '电讯',
      '建筑',
      '港口',
      '航空',
      '装备',
      '化学',
      '制药',
      '交通',
      '通信',
      '电力',
      '家电',
      '互联网',
    ];
    for (final suffix in suffixes) {
      if (sectorName.endsWith(suffix) && sectorName.length > suffix.length) {
        return sectorName.substring(0, sectorName.length - suffix.length);
      }
    }
    return sectorName;
  }

  Future<List<SectorFundItem>> _fetchSectorFundsWithFallback(
      String sectorName, int pageSize) async {
    try {
      var fundMeta = await _searchSectorFunds(sectorName, pageSize);
      if (fundMeta.isEmpty) {
        final keyword = _extractSectorKeyword(sectorName);
        if (keyword != sectorName) {
          fundMeta = await _searchSectorFunds(keyword, pageSize);
        }
      }
      if (fundMeta.isEmpty) return [];

      final codes = fundMeta.keys.toList();
      final estimates = await fetchFundEstimates(codes);

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

      funds.sort((a, b) {
        if (a.hasEstimate && !b.hasEstimate) return -1;
        if (!a.hasEstimate && b.hasEstimate) return 1;
        return b.estimateChange.compareTo(a.estimateChange);
      });

      final activeOnly = funds.where((f) {
        final t = f.type;
        if (t.isEmpty) return true;
        if (t.contains('指数')) return false;
        if (t.contains('ETF')) return false;
        return true;
      }).toList();

      if (activeOnly.isEmpty && funds.isNotEmpty) {
        final etfList = funds;
        final relatedKw = _conceptRelatedKeywords[sectorName];
        final keyword = _extractSectorKeyword(sectorName);
        final searchKeys = <String>{};
        if (relatedKw != null) searchKeys.addAll(relatedKw);
        if (keyword != sectorName) searchKeys.add(keyword);
        searchKeys.remove(sectorName);

        if (searchKeys.isNotEmpty) {
          final extraMeta = <String, FundMeta>{};
          final seenCodes = etfList.map((f) => f.code).toSet();
          final maxExtra = (pageSize ~/ 2).clamp(5, 30);
          for (final key in searchKeys) {
            if (extraMeta.length >= maxExtra) break;
            final batch = await _searchSectorFunds(key, maxExtra);
            for (final entry in batch.entries) {
              if (!seenCodes.contains(entry.key) &&
                  extraMeta.length < maxExtra) {
                extraMeta[entry.key] = entry.value;
                seenCodes.add(entry.key);
              }
            }
          }
          if (extraMeta.isNotEmpty) {
            final extraCodes = extraMeta.keys.toList();
            final extraEstimates = await fetchFundEstimates(extraCodes);
            final extraFunds = extraMeta.values.map((meta) {
              final est = extraEstimates[meta.code];
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
            final extraActive = extraFunds.where((f) {
              final t = f.type;
              if (t.isEmpty) return true;
              if (t.contains('指数')) return false;
              if (t.contains('ETF')) return false;
              return true;
            }).toList();
            return [...etfList, ...extraActive];
          }
        }
        return etfList;
      }

      return activeOnly;
    } catch (e) {
      debugPrint('[API] fetchSectorFunds error: $e');
      return [];
    }
  }

  Future<Map<String, FundMeta>> _searchSectorFunds(
      String keyword, int pageSize) async {
    final response = await dio.get(
      'https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx',
      queryParameters: {
        'm': '1',
        'cb': '',
        'key': keyword,
        'pagesize': pageSize.toString()
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
    if (errCode != 0) return {};
    final items = data['Datas'] as List? ?? [];
    if (items.isEmpty) return {};

    final fundMeta = <String, FundMeta>{};
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      if ((map['CATEGORYDESC'] ?? '').toString() != '基金') continue;
      final code = (map['CODE'] ?? '').toString();
      final name = (map['NAME'] ?? '').toString();
      if (code.isEmpty || name.isEmpty) continue;
      final baseInfo = map['FundBaseInfo'] as Map<String, dynamic>?;
      fundMeta[code] = FundMeta(
        code: code,
        name: name,
        type: (baseInfo?['FTYPE'] ?? '').toString(),
        company: (baseInfo?['JJGS'] ?? '').toString(),
      );
    }
    return fundMeta;
  }

  Future<List<List<StockFundHolder>>> _batchFetchStockHolders(
      List<String> stockCodes,
      {int concurrency = 15}) async {
    final results = <List<StockFundHolder>>[];
    for (var i = 0; i < stockCodes.length; i += concurrency) {
      final chunk =
          stockCodes.sublist(i, (i + concurrency).clamp(0, stockCodes.length));
      final chunkResults = await Future.wait(
        chunk.map((code) => _fetchStockFundHolders(code)
            .catchError((e) => <StockFundHolder>[])),
      );
      results.addAll(chunkResults);
    }
    return results;
  }

  Future<List<StockFundHolder>> _fetchStockFundHolders(String stockCode) async {
    try {
      final response = await dio.get(
        'https://datacenter-web.eastmoney.com/api/data/v1/get',
        queryParameters: {
          'reportName': 'RPT_MAINDATA_MAIN_POSITIONDETAILS',
          'columns':
              'HOLDER_CODE,HOLDER_NAME,PARENT_ORG_CODE,PARENT_ORG_NAME,ORG_TYPE,TOTAL_SHARES,HOLD_MARKET_CAP,REPORT_DATE,SECURITY_CODE',
          'filter': '(SECURITY_CODE="$stockCode")(ORG_TYPE_CODE="1")',
          'pageNumber': '1',
          'pageSize': '100',
          'sortTypes': '-1',
          'sortColumns': 'REPORT_DATE',
          'source': 'WEB',
          'client': 'WEB',
        },
        options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 10)),
      );

      final text = utf8.decode(response.data as Uint8List);
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['success'] != true || data['result'] == null) return [];

      final result = data['result'] as Map<String, dynamic>;
      final list = result['data'] as List? ?? [];

      final seen = <String>{};
      final holders = <StockFundHolder>[];
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final holderCode = map['HOLDER_CODE']?.toString() ?? '';
        final holderName = map['HOLDER_NAME']?.toString() ?? '';
        if (holderCode.isEmpty || holderName.isEmpty) continue;
        if (seen.contains(holderCode)) continue;
        seen.add(holderCode);
        holders.add(StockFundHolder(
          stockCode: stockCode,
          holderCode: holderCode,
          holderName: holderName,
          parentOrgCode: map['PARENT_ORG_CODE']?.toString() ?? '',
          parentOrgName: map['PARENT_ORG_NAME']?.toString() ?? '',
          holdingMarketCap: (map['HOLD_MARKET_CAP'] as num?)?.toDouble() ?? 0,
          reportDate: map['REPORT_DATE']?.toString() ?? '',
        ));
      }
      return holders;
    } catch (e) {
      debugPrint('[API] _fetchStockFundHolders $stockCode error: $e');
      return [];
    }
  }

  String _inferFundType(String fundName) {
    if (fundName.contains('ETF') ||
        (fundName.contains('指数') && !fundName.contains('增强'))) {
      return '指数型-股票';
    }
    if (fundName.contains('混合') ||
        fundName.contains('灵活') ||
        fundName.contains('平衡')) {
      return '混合型';
    }
    if (fundName.contains('债券') ||
        fundName.contains('纯债') ||
        fundName.contains('短债')) {
      return '债券型';
    }
    if (fundName.contains('货币') || fundName.contains('现金')) return '货币型';
    if (fundName.contains('QDII')) return 'QDII';
    if (fundName.contains('联接')) return '指数型-股票';
    if (fundName.contains('LOF')) return '混合型';
    return '混合型';
  }
}
