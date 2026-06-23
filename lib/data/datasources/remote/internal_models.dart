import '../../../domain/entities/fund_entity.dart';

/// pingzhongdata 解析结果
class PzData {
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
  List<dynamic> millionCopiesIncome = []; // 货币基金：每万份收益
  List<dynamic> fluctuationScale = [];
  List<String> stockCodes = [];

  // 行业配置：Data_IndustryAllocation 格式 { series: [{ data: [{name, y}] }] }
  List<dynamic> industryItems = [];

  // 资产配置：Data_assetAllocation 格式 { series: [{name, data:[...]}] }
  List<dynamic> assetSeries = [];
}

/// 蛋卷基金 API 解析结果
class DjData {
  final int fetchedAt;
  final String code;
  final String sourceMark; // "年报" / "季报"
  final String endDate; // "2025-12-31"

  // 资产配置
  final double stockPercent;
  final double cashPercent;
  final double otherPercent;

  // 重仓股列表（已转为 StockHolding）
  final List<StockHolding> stockList;

  // 行业分布（已转为 IndustryAllocation）
  final List<IndustryAllocation> industryList;

  DjData({
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

  factory DjData.fromJson(Map<String, dynamic> data, String code) {
    final position = data['fund_position'] as Map<String, dynamic>? ?? {};

    final stockPct = (position['stock_percent'] as num?)?.toDouble() ?? 0.0;
    final cashPct = (position['cash_percent'] as num?)?.toDouble() ?? 0.0;
    final otherPct = (position['other_percent'] as num?)?.toDouble() ?? 0.0;

    final stockRaw = position['stock_list'] as List? ?? [];
    final stocks = stockRaw.map((item) {
      final m = item as Map<String, dynamic>;
      return StockHolding(
        stockCode: (m['code'] ?? '').toString(),
        stockName: (m['name'] ?? '').toString(),
        holdingRatio: (m['percent'] as num?)?.toDouble() ?? 0.0,
        holdingAmount: '',
        changeFromLast: (m['change_of_pre_quarter'] ?? '--').toString(),
        currentPrice: (m['current_price'] as num?)?.toDouble(),
        changePercent: (m['change_percentage'] as num?)?.toDouble(),
        industryLabel: m['industry_label'] as String?,
        isAMarket: m['amarket'] as bool? ?? true,
        changeOfPreQuarter: m['change_of_pre_quarter'] as String?,
      );
    }).toList();

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
          labelMap[s.industryLabel!] =
              (labelMap[s.industryLabel!] ?? 0) + s.holdingRatio;
        }
      }
      final sorted = labelMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      industries.addAll(sorted.map((e) => IndustryAllocation(
            name: e.key,
            industryCode: null,
            percent: double.parse(e.value.toStringAsFixed(2)),
            color: null,
          )));
    }

    return DjData(
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

/// 重仓股解析中间结果
class StockRaw {
  final String stockCode;
  final String stockName;
  final double holdingRatio;
  final String holdingAmount;
  final String changeFromLast;

  StockRaw({
    required this.stockCode,
    required this.stockName,
    required this.holdingRatio,
    required this.holdingAmount,
    required this.changeFromLast,
  });
}

/// 板块基金搜索辅助类
class FundMeta {
  final String code;
  final String name;
  final String type;
  final String company;

  const FundMeta({
    required this.code,
    required this.name,
    this.type = '',
    this.company = '',
  });
}

/// 单只股票被单只基金持有的一条记录
class StockFundHolder {
  final String stockCode;
  final String holderCode;
  final String holderName;
  final String parentOrgCode;
  final String parentOrgName;
  final double holdingMarketCap;
  final String reportDate;

  StockFundHolder({
    required this.stockCode,
    required this.holderCode,
    required this.holderName,
    required this.parentOrgCode,
    required this.parentOrgName,
    required this.holdingMarketCap,
    required this.reportDate,
  });
}

/// 聚合后的基金汇总
class AggregatedFund {
  final String code;
  String name;
  final String parentOrgName;
  double totalHolding;
  int stockCount;
  final Set<String> stocks;

  AggregatedFund({
    required this.code,
    required this.name,
    required this.parentOrgName,
    required this.totalHolding,
    required this.stockCount,
    required this.stocks,
  });
}
