/// 基金实时估值数据（天天基金 JSONP 返回格式）
class FundEstimate {
  final String fundcode; // 基金代码
  final String name; // 基金名称
  final String jzrq; // 净值日期
  final double dwjz; // 单位净值（上一交易日）
  final double gsz; // 估算净值
  final double gszzl; // 估算涨跌幅（%）
  final String gztime; // 估值时间

  FundEstimate({
    required this.fundcode,
    required this.name,
    required this.jzrq,
    required this.dwjz,
    required this.gsz,
    required this.gszzl,
    required this.gztime,
  });

  factory FundEstimate.fromJson(Map<String, dynamic> json) {
    return FundEstimate(
      fundcode: json['fundcode'] ?? '',
      name: json['name'] ?? '',
      jzrq: json['jzrq'] ?? '',
      dwjz: double.tryParse(json['dwjz'] ?? '') ?? 0,
      gsz: double.tryParse(json['gsz'] ?? '') ?? 0,
      gszzl: double.tryParse(json['gszzl'] ?? '') ?? 0,
      gztime: json['gztime'] ?? '',
    );
  }
}

/// 基金基本信息（基金列表项）
class FundInfo {
  final String code;
  final String name;
  final String type;
  final String pinyin;

  FundInfo({
    required this.code,
    required this.name,
    required this.type,
    required this.pinyin,
  });

  factory FundInfo.fromJson(List<dynamic> json) {
    return FundInfo(
      code: json.isNotEmpty ? json[0] ?? '' : '',
      pinyin: json.length > 1 ? json[1] ?? '' : '',
      name: json.length > 2 ? json[2] ?? '' : '',
      type: json.length > 3 ? json[3] ?? '' : '',
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 持仓与交易
// ═══════════════════════════════════════════════════════════

/// 持仓记录
class HoldingRecord {
  final String code;
  final String name;
  final String? fundType;
  final String shareClass; // A 或 C
  final double amount; // 持有金额（元）
  final double buyNetValue; // 买入时净值
  final double shares; // 持有份额
  final String buyDate; // YYYY-MM-DD
  final int holdingDays;
  final int createdAt;
  final double? buyFeeRate;
  final bool? buyFeeDeducted;
  final double? buyFeeAmount;
  final double? sellFeeRate;
  final double? serviceFeeRate;
  final double? serviceFeeDeducted;
  final String? lastFeeDate;

  HoldingRecord({
    required this.code,
    required this.name,
    this.fundType,
    required this.shareClass,
    required this.amount,
    required this.buyNetValue,
    required this.shares,
    required this.buyDate,
    required this.holdingDays,
    required this.createdAt,
    this.buyFeeRate,
    this.buyFeeDeducted,
    this.buyFeeAmount,
    this.sellFeeRate,
    this.serviceFeeRate,
    this.serviceFeeDeducted,
    this.lastFeeDate,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'fundType': fundType,
        'shareClass': shareClass,
        'amount': amount,
        'buyNetValue': buyNetValue,
        'shares': shares,
        'buyDate': buyDate,
        'holdingDays': holdingDays,
        'createdAt': createdAt,
        'buyFeeRate': buyFeeRate,
        'buyFeeDeducted': buyFeeDeducted,
        'buyFeeAmount': buyFeeAmount,
        'sellFeeRate': sellFeeRate,
        'serviceFeeRate': serviceFeeRate,
        'serviceFeeDeducted': serviceFeeDeducted,
        'lastFeeDate': lastFeeDate,
      };

  factory HoldingRecord.fromJson(Map<String, dynamic> json) {
    return HoldingRecord(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      fundType: json['fundType'],
      shareClass: json['shareClass'] ?? 'A',
      amount: (json['amount'] ?? 0).toDouble(),
      buyNetValue: (json['buyNetValue'] ?? 0).toDouble(),
      shares: (json['shares'] ?? 0).toDouble(),
      buyDate: json['buyDate'] ?? '',
      holdingDays: json['holdingDays'] ?? 0,
      createdAt: json['createdAt'] ?? 0,
      buyFeeRate: json['buyFeeRate']?.toDouble(),
      buyFeeDeducted: json['buyFeeDeducted'],
      buyFeeAmount: json['buyFeeAmount']?.toDouble(),
      sellFeeRate: json['sellFeeRate']?.toDouble(),
      serviceFeeRate: json['serviceFeeRate']?.toDouble(),
      serviceFeeDeducted: json['serviceFeeDeducted']?.toDouble(),
      lastFeeDate: json['lastFeeDate'],
    );
  }

  HoldingRecord copyWith({
    String? code,
    String? name,
    String? fundType,
    String? shareClass,
    double? amount,
    double? buyNetValue,
    double? shares,
    String? buyDate,
    int? holdingDays,
    int? createdAt,
    double? buyFeeRate,
    bool? buyFeeDeducted,
    double? buyFeeAmount,
    double? sellFeeRate,
    double? serviceFeeRate,
    double? serviceFeeDeducted,
    String? lastFeeDate,
  }) {
    return HoldingRecord(
      code: code ?? this.code,
      name: name ?? this.name,
      fundType: fundType ?? this.fundType,
      shareClass: shareClass ?? this.shareClass,
      amount: amount ?? this.amount,
      buyNetValue: buyNetValue ?? this.buyNetValue,
      shares: shares ?? this.shares,
      buyDate: buyDate ?? this.buyDate,
      holdingDays: holdingDays ?? this.holdingDays,
      createdAt: createdAt ?? this.createdAt,
      buyFeeRate: buyFeeRate ?? this.buyFeeRate,
      buyFeeDeducted: buyFeeDeducted ?? this.buyFeeDeducted,
      buyFeeAmount: buyFeeAmount ?? this.buyFeeAmount,
      sellFeeRate: sellFeeRate ?? this.sellFeeRate,
      serviceFeeRate: serviceFeeRate ?? this.serviceFeeRate,
      serviceFeeDeducted: serviceFeeDeducted ?? this.serviceFeeDeducted,
      lastFeeDate: lastFeeDate ?? this.lastFeeDate,
    );
  }
}

/// 历史净值记录
class NetValueRecord {
  final String date;
  final double netValue;
  final double totalValue;
  final double changeRate;

  NetValueRecord({
    required this.date,
    required this.netValue,
    required this.totalValue,
    required this.changeRate,
  });
}

/// 重仓股票（支持蛋卷/东方财富双源）
class StockHolding {
  final String stockCode;
  final String stockName;
  final double holdingRatio;
  final String holdingAmount;
  final String changeFromLast;

  // 蛋卷 API 扩展字段
  final double? currentPrice;     // 实时股价
  final double? changePercent;    // 今日涨跌幅 %
  final String? industryLabel;    // 行业标签（如 "食品饮料"）
  final bool isAMarket;           // 是否 A 股
  final String? changeOfPreQuarter; // 较上期持仓变动

  StockHolding({
    required this.stockCode,
    required this.stockName,
    required this.holdingRatio,
    required this.holdingAmount,
    required this.changeFromLast,
    this.currentPrice,
    this.changePercent,
    this.industryLabel,
    this.isAMarket = true,
    this.changeOfPreQuarter,
  });
}

/// 自选基金项
class WatchlistItem {
  final String code;
  final String name;
  final String? estimateValue;
  final String? estimateChange;
  final String? estimateTime;
  final String? lastValue;
  final bool loading;
  final String dataSource; // nav / estimate

  WatchlistItem({
    required this.code,
    required this.name,
    this.estimateValue,
    this.estimateChange,
    this.estimateTime,
    this.lastValue,
    this.loading = false,
    this.dataSource = 'estimate',
  });
}

/// 持仓汇总
class HoldingSummary {
  final double totalValue;
  final double totalCost;
  final double totalProfit;
  final double totalProfitRate;
  final double todayProfit;

  HoldingSummary({
    required this.totalValue,
    required this.totalCost,
    required this.totalProfit,
    required this.totalProfitRate,
    required this.todayProfit,
  });
}

/// 交易类型
enum TradeType { buy, sell, dividend, autoInvest }

/// 交易状态
enum TradeStatus { completed, pending, processing, failed, cancelled }

/// 交易记录
class TradeRecord {
  final String id;
  final String code;
  final String name;
  final TradeType type;
  final String date;
  final double amount;
  final double netValue;
  final double shares;
  final double fee;
  final String? remark;
  final int createdAt;
  final TradeStatus? status;

  TradeRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.date,
    required this.amount,
    required this.netValue,
    required this.shares,
    required this.fee,
    this.remark,
    required this.createdAt,
    this.status,
  });
}

// ═══════════════════════════════════════════════════════════
// 市场行情
// ═══════════════════════════════════════════════════════════

/// 大盘指数
class MarketIndex {
  final String code;
  final String name;
  final double current;
  final double change;
  final double changeRate;
  final double volume;

  MarketIndex({
    required this.code,
    required this.name,
    required this.current,
    required this.change,
    required this.changeRate,
    required this.volume,
  });
}

/// 基金排行项
class FundRankItem {
  final String code;
  final String name;
  final String type;
  final double netValue;
  final double dayChange;
  final double weekChange;
  final double monthChange;
  final double threeMonthChange;
  final double halfYearChange;
  final double yearChange;

  FundRankItem({
    required this.code,
    required this.name,
    required this.type,
    required this.netValue,
    required this.dayChange,
    required this.weekChange,
    required this.monthChange,
    this.threeMonthChange = 0,
    this.halfYearChange = 0,
    required this.yearChange,
  });
}

/// 基金费率信息
class FundFeeInfo {
  final String code;
  final String shareClass;
  final double buyFeeRate;
  final List<FeeRateRange> sellFeeRates;
  final double serviceFeeRate;
  final double managementFeeRate;
  final double custodianFeeRate;

  FundFeeInfo({
    required this.code,
    required this.shareClass,
    required this.buyFeeRate,
    required this.sellFeeRates,
    required this.serviceFeeRate,
    required this.managementFeeRate,
    required this.custodianFeeRate,
  });
}

class FeeRateRange {
  final int minDays;
  final int maxDays;
  final double rate;

  FeeRateRange({
    required this.minDays,
    required this.maxDays,
    required this.rate,
  });
}

/// 阶段涨幅
class PeriodReturn {
  final String period;
  final String label;
  final double returnRate;
  final String? rankInSimilar;
  final String? totalInSimilar;

  PeriodReturn({
    required this.period,
    required this.label,
    required this.returnRate,
    this.rankInSimilar,
    this.totalInSimilar,
  });
}

/// 基金准确数据（综合估值+净值）
class FundAccurateData {
  final String code;
  final String name;
  final double nav;
  final String navDate;
  final double navChange;
  final double estimate;
  final String estimateTime;
  final double estimateChange;
  final double prevClose;
  final double currentValue;
  final double dayChange;
  final String dataSource; // nav / estimate / fallback
  final String fundType; // 基金类型
  final String company; // 基金公司
  final String establishDate; // 成立日期
  final String scale; // 基金规模
  final double? riskLevel; // 风险等级
  final String? manager; // 基金经理

  FundAccurateData({
    required this.code,
    required this.name,
    required this.nav,
    required this.navDate,
    required this.navChange,
    required this.estimate,
    required this.estimateTime,
    required this.estimateChange,
    required this.prevClose,
    required this.currentValue,
    required this.dayChange,
    required this.dataSource,
    this.fundType = '',
    this.company = '',
    this.establishDate = '',
    this.scale = '',
    this.riskLevel,
    this.manager,
  });
}

/// 基金经理信息
class FundManagerInfo {
  final String id;
  final String name;
  final String photo;
  final String company;
  final int workingDays;
  final double managedScale;
  final int managedCount;
  final double bestReturn;
  final double annualReturn;

  FundManagerInfo({
    required this.id,
    required this.name,
    required this.photo,
    required this.company,
    required this.workingDays,
    required this.managedScale,
    required this.managedCount,
    required this.bestReturn,
    required this.annualReturn,
  });
}

/// 行业配置（支持蛋卷/东方财富双源）
class IndustryAllocation {
  final String name;
  final String? industryCode; // 证监会行业代码（蛋卷: "S34"）
  final String? industry; // 别名
  final double percent;
  final double? proportion; // 别名
  final String? color; // 蛋卷提供颜色（如 "#287DFF"）

  IndustryAllocation({
    required this.name,
    this.industryCode,
    this.industry,
    required this.percent,
    this.proportion,
    this.color,
  });
}

/// 资产配置
class AssetAllocation {
  final double stocks;
  final double bonds;
  final double cash;
  final double others;

  AssetAllocation({
    required this.stocks,
    required this.bonds,
    required this.cash,
    required this.others,
  });
}

// ═══════════════════════════════════════════════════════════
// 板块与新闻
// ═══════════════════════════════════════════════════════════

/// 关联板块信息
class SectorInfo {
  final String code;   // 板块代码
  final String name;   // 板块名称
  final double dayReturn; // 今日涨跌幅
  final String streak; // 连涨/描述

  SectorInfo({
    required this.code,
    required this.name,
    required this.dayReturn,
    required this.streak,
  });
}

/// 财经新闻
class NewsItem {
  final String id;
  final String title;
  final String source;
  final String time;
  final String url;
  final String? summary;
  final String? digest;
  final String? imageUrl;
  final String? category;

  NewsItem({
    required this.id,
    required this.title,
    required this.source,
    required this.time,
    required this.url,
    this.summary,
    this.digest,
    this.imageUrl,
    this.category,
  });
}

/// 板块排行项
class SectorRankItem {
  final String code;   // 板块代码 (如 BK1395)
  final String name;   // 板块名称
  final double price;  // 当前点位/价格
  final double changePercent; // 涨跌幅 %
  final double change; // 涨跌额

  SectorRankItem({
    required this.code,
    required this.name,
    required this.price,
    required this.changePercent,
    required this.change,
  });
}

/// 板块成分股/基（板块详情页使用）
class SectorConstituentItem {
  final String code;   // 股票/基金代码
  final String name;   // 名称
  final double price;  // 当前价
  final double changePercent; // 涨跌幅 %
  final double change; // 涨跌额
  final double? marketCap; // 总市值（亿）
  final double? turnoverRate; // 换手率 %

  SectorConstituentItem({
    required this.code,
    required this.name,
    this.price = 0,
    this.changePercent = 0,
    this.change = 0,
    this.marketCap,
    this.turnoverRate,
  });
}

// ═══════════════════════════════════════════════════════════
// 扩展 / 派生模型
// ═══════════════════════════════════════════════════════════

/// 持仓含盈亏（计算后的扩展模型）
class HoldingWithProfit extends HoldingRecord {
  final double? nav;
  final String? navDate;
  final double? navChange;
  final double? estimate;
  final String? estimateTime;
  final double? estimateChange;
  final double marketValue;
  final String todayChange;
  final double todayProfit;
  final double profit;
  final String profitRate;
  final String valueSource;
  final List<String>? sectors;
  final String changeLabel; // 显示标签：当日估算涨跌/当日涨跌/昨日涨跌/上一交易日涨跌
  final String changeUpdateTime; // 更新时间：14:55更新 / 04-20净值
  final bool navUpdated; // 净值是否已更新（navDate == 今天）
  final bool hasError; // API获取失败标记

  HoldingWithProfit({
    required super.code,
    required super.name,
    super.fundType,
    required super.shareClass,
    required super.amount,
    required super.buyNetValue,
    required super.shares,
    required super.buyDate,
    required super.holdingDays,
    required super.createdAt,
    super.buyFeeRate,
    super.buyFeeDeducted,
    super.buyFeeAmount,
    super.sellFeeRate,
    super.serviceFeeRate,
    super.serviceFeeDeducted,
    super.lastFeeDate,
    this.nav,
    this.navDate,
    this.navChange,
    this.estimate,
    this.estimateTime,
    this.estimateChange,
    required this.marketValue,
    required this.todayChange,
    required this.todayProfit,
    required this.profit,
    required this.profitRate,
    required this.valueSource,
    this.sectors,
    required this.changeLabel,
    required this.changeUpdateTime,
    required this.navUpdated,
    this.hasError = false,
  });
}

/// 板块关联基金项（板块详情页用）
class SectorFundItem {
  final String code;            // 基金代码
  final String name;           // 基金名称
  final String type;           // 基金类型（如 指数型-股票）
  final String fundCompany;    // 基金公司
  final double netValue;       // 单位净值
  final double estimateChange; // 估算涨跌幅(%)
  final String estimateTime;   // 估值时间
  final bool hasEstimate;      // 是否有有效估值数据

  const SectorFundItem({
    required this.code,
    required this.name,
    this.type = '',
    this.fundCompany = '',
    this.netValue = 0,
    this.estimateChange = 0,
    this.estimateTime = '',
    this.hasEstimate = false,
  });
}
