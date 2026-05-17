import 'package:equatable/equatable.dart';

/// 基金基本信息
class FundInfo extends Equatable {
  final String fundCode;
  final String fundName;
  final String fundType;        // 基金类型: 股票型/混合型/债券型等
  final String fundCompany;     // 基金公司
  final String establishDate;   // 成立日期
  final double navUnit;         // 单位净值
  final double navAccumulated;  // 累计净值
  final double navDate;        // 净值日期（时间戳）
  final double dayGrowth;       // 日增长率(%)
  final double monthGrowth;     // 月增长率(%)
  final double yearGrowth;      // 近1年收益率(%)
  final double totalAssets;     // 基金规模(亿元)
  final double managerSince;    // 经理任职天数
  final String managerName;     // 经理姓名
  final int holdingCount;       // 持有人数
  final double feeRate;         // 管理费率
  final double minInvestAmount; // 最小申购金额

  const FundInfo({
    required this.fundCode,
    required this.fundName,
    this.fundType = '',
    this.fundCompany = '',
    this.establishDate = '',
    this.navUnit = 0.0,
    this.navAccumulated = 0.0,
    this.navDate = 0.0,
    this.dayGrowth = 0.0,
    this.monthGrowth = 0.0,
    this.yearGrowth = 0.0,
    this.totalAssets = 0.0,
    this.managerSince = 0.0,
    this.managerName = '',
    this.holdingCount = 0,
    this.feeRate = 0.0,
    this.minInvestAmount = 10.0,
  });

  @override
  List<Object?> get props => [fundCode, fundName, navUnit, dayGrowth];

  Map<String, dynamic> toJson() => {
    'fund_code': fundCode, 'fund_name': fundName, 'fund_type': fundType,
    'fund_company': fundCompany, 'establish_date': establishDate,
    'nav_unit': navUnit, 'nav_accumulated': navAccumulated,
    'day_growth': dayGrowth, 'month_growth': monthGrowth,
    'year_growth': yearGrowth, 'total_assets': totalAssets,
    'manager_name': managerName, 'fee_rate': feeRate,
    'min_invest_amount': minInvestAmount,
  };

  factory FundInfo.fromJson(Map<String, dynamic> json) => FundInfo(
    fundCode: (json['fundCode'] ?? json['fund_code'] ?? '').toString(),
    fundName: (json['fundName'] ?? json['fund_name'] ?? '').toString(),
    fundType: (json['fundType'] ?? json['fund_type'] ?? '').toString(),
    fundCompany: (json['fundCompany'] ?? json['fund_company'] ?? '').toString(),
    establishDate: (json['establishDate'] ?? json['establish_date'] ?? '').toString(),
    navUnit: _parseD(json['navUnit'] ?? json['nav_unit']),
    navAccumulated: _parseD(json['navAccumulated'] ?? json['nav_accumulated']),
    dayGrowth: _parseD(json['dayGrowth'] ?? json['day_growth']),
    monthGrowth: _parseD(json['monthGrowth'] ?? json['month_growth']),
    yearGrowth: _parseD(json['yearGrowth'] ?? json['year_growth']),
    totalAssets: _parseD(json['totalAssets'] ?? json['total_assets']),
    managerName: (json['managerName'] ?? json['manager_name'] ?? '').toString(),
    feeRate: _parseD(json['feeRate'] ?? json['fee_rate']),
    minInvestAmount: _parseD(json['minInvestAmount'] ?? json['min_invest_amount'], fallback: 10.0),
  );

  static double _parseD(dynamic v, {double fallback = 0.0}) =>
      v == null ? fallback : double.tryParse(v.toString()) ?? fallback;

  FundInfo copyWith({
    String? fundCode,
    String? fundName,
    String? fundType,
    String? fundCompany,
    String? establishDate,
    double? navUnit,
    double? navAccumulated,
    double? navDate,
    double? dayGrowth,
    double? monthGrowth,
    double? yearGrowth,
    double? totalAssets,
    double? managerSince,
    String? managerName,
    int? holdingCount,
    double? feeRate,
    double? minInvestAmount,
  }) {
    return FundInfo(
      fundCode: fundCode ?? this.fundCode,
      fundName: fundName ?? this.fundName,
      fundType: fundType ?? this.fundType,
      fundCompany: fundCompany ?? this.fundCompany,
      establishDate: establishDate ?? this.establishDate,
      navUnit: navUnit ?? this.navUnit,
      navAccumulated: navAccumulated ?? this.navAccumulated,
      dayGrowth: dayGrowth ?? this.dayGrowth,
      monthGrowth: monthGrowth ?? this.monthGrowth,
      yearGrowth: yearGrowth ?? this.yearGrowth,
      totalAssets: totalAssets ?? this.totalAssets,
      managerSince: managerSince ?? this.managerSince,
      managerName: managerName ?? this.managerName,
      holdingCount: holdingCount ?? this.holdingCount,
      feeRate: feeRate ?? this.feeRate,
      minInvestAmount: minInvestAmount ?? this.minInvestAmount,
    );
  }
}
