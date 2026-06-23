import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum DetailStatus { initial, loading, loaded, error }

// 净值走势可选期限
enum NavPeriod { oneMonth, threeMonth, sixMonth, oneYear }

extension NavPeriodExt on NavPeriod {
  String get label {
    switch (this) {
      case NavPeriod.oneMonth:
        return '近1月';
      case NavPeriod.threeMonth:
        return '近3月';
      case NavPeriod.sixMonth:
        return '近6月';
      case NavPeriod.oneYear:
        return '近1年';
    }
  }

  int get days {
    switch (this) {
      case NavPeriod.oneMonth:
        return 30;
      case NavPeriod.threeMonth:
        return 90;
      case NavPeriod.sixMonth:
        return 180;
      case NavPeriod.oneYear:
        return 365;
    }
  }
}

class DetailState extends Equatable {
  final DetailStatus status;
  final FundAccurateData? accurateData;

  /// 今日实时估算（来自 fundgz，已内嵌到 accurateData 中）
  /// estimateChange = 估算涨跌幅，estimate = 估算净值，estimateTime = 更新时间
  final List<NetValueRecord> navHistory;
  final List<PeriodReturn> periodReturns;
  final List<StockHolding> stockHoldings;
  final List<IndustryAllocation> industryAllocation;
  final AssetAllocation? assetAllocation;
  final List<FundManagerInfo> managers;
  final String? errorMessage;
  final bool isRefreshingNavHistory;
  final bool isRefreshingPeriod;
  final NavPeriod selectedNavPeriod;

  const DetailState({
    this.status = DetailStatus.initial,
    this.accurateData,
    this.navHistory = const [],
    this.periodReturns = const [],
    this.stockHoldings = const [],
    this.industryAllocation = const [],
    this.assetAllocation,
    this.managers = const [],
    this.errorMessage,
    this.isRefreshingNavHistory = false,
    this.isRefreshingPeriod = false,
    this.selectedNavPeriod = NavPeriod.oneMonth,
  });

  /// 顶部显示用的涨跌幅：优先用今日估算，其次用昨日净值变化
  double get displayChange {
    final d = accurateData;
    if (d == null) return 0;
    // 估算涨跌幅有效则用估算，否则用昨日涨跌
    return d.estimateChange != 0 ? d.estimateChange : d.dayChange;
  }

  /// 顶部显示用的净值：优先用今日估算净值，其次用最新净值
  double get displayNav {
    final d = accurateData;
    if (d == null) return 0;
    return d.estimate != 0 ? d.estimate : d.nav;
  }

  DetailState copyWith({
    DetailStatus? status,
    FundAccurateData? accurateData,
    List<NetValueRecord>? navHistory,
    List<PeriodReturn>? periodReturns,
    List<StockHolding>? stockHoldings,
    List<IndustryAllocation>? industryAllocation,
    AssetAllocation? assetAllocation,
    List<FundManagerInfo>? managers,
    String? errorMessage,
    bool? isRefreshingNavHistory,
    bool? isRefreshingPeriod,
    NavPeriod? selectedNavPeriod,
  }) {
    return DetailState(
      status: status ?? this.status,
      accurateData: accurateData ?? this.accurateData,
      navHistory: navHistory ?? this.navHistory,
      periodReturns: periodReturns ?? this.periodReturns,
      stockHoldings: stockHoldings ?? this.stockHoldings,
      industryAllocation: industryAllocation ?? this.industryAllocation,
      assetAllocation: assetAllocation ?? this.assetAllocation,
      managers: managers ?? this.managers,
      errorMessage: errorMessage ?? this.errorMessage,
      isRefreshingNavHistory:
          isRefreshingNavHistory ?? this.isRefreshingNavHistory,
      isRefreshingPeriod: isRefreshingPeriod ?? this.isRefreshingPeriod,
      selectedNavPeriod: selectedNavPeriod ?? this.selectedNavPeriod,
    );
  }

  @override
  List<Object?> get props => [
        status,
        accurateData,
        navHistory,
        periodReturns,
        stockHoldings,
        industryAllocation,
        assetAllocation,
        managers,
        errorMessage,
        isRefreshingNavHistory,
        isRefreshingPeriod,
        selectedNavPeriod,
      ];
}
