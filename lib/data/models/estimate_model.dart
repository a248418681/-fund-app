import 'package:equatable/equatable.dart';

/// 基金实时估值（盘中估算）
class FundEstimate extends Equatable {
  final String fundCode;
  final String fundName;
  final double estimateNav;       // 估算净值
  final double estimateGrowth;    // 估算涨跌幅(%)
  final String estimateTime;      // 估值时间（原为 double，改为 String 匹配 API）
  final double yesterdayNav;      // 昨日净值
  final double maxEstimate;       // 当日最高估值
  final double minEstimate;       // 当日最低估值

  const FundEstimate({
    required this.fundCode,
    required this.fundName,
    required this.estimateNav,
    required this.estimateGrowth,
    required this.estimateTime,
    this.yesterdayNav = 0.0,
    this.maxEstimate = 0.0,
    this.minEstimate = 0.0,
  });

  /// 从 API 响应创建（映射天天基金 JSONP 字段名）
  factory FundEstimate.fromJson(Map<String, dynamic> json) {
    return FundEstimate(
      fundCode: json['fundcode']?.toString() ?? '',
      fundName: json['name']?.toString() ?? '',
      estimateNav: double.tryParse(json['gsz']?.toString() ?? '0') ?? 0.0,
      estimateGrowth: double.tryParse(json['gszzl']?.toString() ?? '0') ?? 0.0,
      estimateTime: json['gztime']?.toString() ?? '',
      yesterdayNav: double.tryParse(json['dwjz']?.toString() ?? '0') ?? 0.0,
      maxEstimate: 0.0, // API 不提供
      minEstimate: 0.0, // API 不提供
    );
  }

  /// 从 FundAccurateData 转换（用于 DetailState）
  factory FundEstimate.fromAccurateData(dynamic data) {
    return FundEstimate(
      fundCode: data.code?.toString() ?? '',
      fundName: data.name?.toString() ?? '',
      estimateNav: (data.estimate as num?)?.toDouble() ?? 0.0,
      estimateGrowth: (data.estimateChange as num?)?.toDouble() ?? 0.0,
      estimateTime: data.estimateTime?.toString() ?? '',
      yesterdayNav: (data.nav as num?)?.toDouble() ?? 0.0,
      maxEstimate: 0.0,
      minEstimate: 0.0,
    );
  }

  @override
  List<Object?> get props => [fundCode, estimateNav, estimateGrowth];
}
