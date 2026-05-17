import 'package:equatable/equatable.dart';

/// 用户持仓信息
class HoldingItem extends Equatable {
  final String id;
  final String fundCode;
  final String fundName;
  final double shares;           // 持有份额
  final double costPrice;        // 成本单价
  final double currentNav;       // 当前净值
  final double currentEstimate;  // 当前估算值
  final double dayIncome;        // 今日收益
  final double totalIncome;      // 总收益(元)
  final double totalIncomeRate;  // 总收益率(%)
  final double investedAmount;   // 投入金额(元)
  final DateTime buyDate;        // 买入日期
  final bool isFavorite;         // 是否自选
  final String note;             // 备注

  const HoldingItem({
    required this.id,
    required this.fundCode,
    required this.fundName,
    this.shares = 0.0,
    this.costPrice = 0.0,
    this.currentNav = 0.0,
    this.currentEstimate = 0.0,
    this.dayIncome = 0.0,
    this.totalIncome = 0.0,
    this.totalIncomeRate = 0.0,
    this.investedAmount = 0.0,
    required this.buyDate,
    this.isFavorite = false,
    this.note = '',
  });

  @override
  List<Object?> get props => [id, fundCode, shares, totalIncome];

  Map<String, dynamic> toJson() => {
    'id': id, 'fund_code': fundCode, 'fund_name': fundName,
    'shares': shares, 'cost_price': costPrice,
    'current_nav': currentNav, 'current_estimate': currentEstimate,
    'day_income': dayIncome, 'total_income': totalIncome,
    'total_income_rate': totalIncomeRate, 'invested_amount': investedAmount,
    'buy_date': buyDate.toIso8601String(), 'is_favorite': isFavorite, 'note': note,
  };

  factory HoldingItem.fromJson(Map<String, dynamic> json) => HoldingItem(
    id: (json['id'] ?? '').toString(),
    fundCode: (json['fundCode'] ?? json['fund_code'] ?? '').toString(),
    fundName: (json['fundName'] ?? json['fund_name'] ?? '').toString(),
    shares: _parseD(json['shares']),
    costPrice: _parseD(json['costPrice'] ?? json['cost_price']),
    currentNav: _parseD(json['currentNav'] ?? json['current_nav']),
    currentEstimate: _parseD(json['currentEstimate'] ?? json['current_estimate']),
    dayIncome: _parseD(json['dayIncome'] ?? json['day_income']),
    totalIncome: _parseD(json['totalIncome'] ?? json['total_income']),
    totalIncomeRate: _parseD(json['totalIncomeRate'] ?? json['total_income_rate']),
    investedAmount: _parseD(json['investedAmount'] ?? json['invested_amount']),
    buyDate: DateTime.tryParse((json['buyDate'] ?? json['buy_date'] ?? '').toString()) ?? DateTime.now(),
    isFavorite: json['isFavorite'] == true || json['is_favorite'] == true,
    note: (json['note'] ?? '').toString(),
  );

  static double _parseD(dynamic v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  HoldingItem copyWith({
    String? id,
    String? fundCode,
    String? fundName,
    double? shares,
    double? costPrice,
    double? currentNav,
    double? currentEstimate,
    double? dayIncome,
    double? totalIncome,
    double? totalIncomeRate,
    double? investedAmount,
    DateTime? buyDate,
    bool? isFavorite,
    String? note,
  }) {
    return HoldingItem(
      id: id ?? this.id,
      fundCode: fundCode ?? this.fundCode,
      fundName: fundName ?? this.fundName,
      shares: shares ?? this.shares,
      costPrice: costPrice ?? this.costPrice,
      currentNav: currentNav ?? this.currentNav,
      currentEstimate: currentEstimate ?? this.currentEstimate,
      dayIncome: dayIncome ?? this.dayIncome,
      totalIncome: totalIncome ?? this.totalIncome,
      totalIncomeRate: totalIncomeRate ?? this.totalIncomeRate,
      investedAmount: investedAmount ?? this.investedAmount,
      buyDate: buyDate ?? this.buyDate,
      isFavorite: isFavorite ?? this.isFavorite,
      note: note ?? this.note,
    );
  }
}
