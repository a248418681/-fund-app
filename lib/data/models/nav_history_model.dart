import 'package:equatable/equatable.dart';

/// 基金历史净值数据
class NavHistoryData extends Equatable {
  final List<NavHistoryRecord> records;
  final String fundCode;
  final String fundName;
  
  const NavHistoryData({
    required this.records,
    required this.fundCode,
    required this.fundName,
  });
  
  @override
  List<Object?> get props => [fundCode, records.length];
  
  /// 计算期间收益率
  double get periodReturn {
    if (records.length < 2) return 0.0;
    final first = records.first.nav;
    final last = records.last.nav;
    if (first <= 0) return 0.0;
    return ((last - first) / first) * 100;
  }
  
  /// 获取最大回撤
  double get maxDrawdown {
    if (records.isEmpty) return 0.0;
    double peak = records.first.nav;
    double maxDd = 0.0;
    for (final r in records) {
      if (r.nav > peak) peak = r.nav;
      final dd = (peak - r.nav) / peak * 100;
      if (dd > maxDd) maxDd = dd;
    }
    return maxDd;
  }
}

/// 单条净值记录
class NavHistoryRecord extends Equatable {
  final DateTime date;
  final double nav;
  final double accumulatedNav;
  final double dailyGrowth;
  
  const NavHistoryRecord({
    required this.date,
    required this.nav,
    this.accumulatedNav = 0.0,
    this.dailyGrowth = 0.0,
  });
  
  @override
  List<Object?> get props => [date, nav, dailyGrowth];
}
