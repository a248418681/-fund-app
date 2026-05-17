import 'package:equatable/equatable.dart';
import '../../../../data/models/fund_model.dart';
import '../../../../data/models/nav_history_model.dart';
import '../../../../data/models/estimate_model.dart';

class DetailState extends Equatable {
  final FundInfo? fund;
  final FundEstimate? estimate;
  final NavHistoryData? navHistory;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;

  const DetailState({
    this.fund,
    this.estimate,
    this.navHistory,
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
  });

  @override
  List<Object?> get props => [fund, estimate, navHistory, isLoading, isRefreshing, error];

  DetailState copyWith({
    FundInfo? fund,
    FundEstimate? estimate,
    NavHistoryData? navHistory,
    bool? isLoading,
    bool? isRefreshing,
    bool clearFund = false,
    bool clearEstimate = false,
    bool clearError = false,
    String? error,
  }) {
    return DetailState(
      fund: clearFund ? null : (fund ?? this.fund),
      estimate: clearEstimate ? null : (estimate ?? this.estimate),
      navHistory: navHistory ?? this.navHistory,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

abstract class DetailEvent extends Equatable {
  const DetailEvent();
  @override
  List<Object?> get props => [];
}

class LoadFundDetail extends DetailEvent {
  final String fundCode;
  const LoadFundDetail(this.fundCode);
  @override
  List<Object?> get props => [fundCode];
}

class RefreshDetail extends DetailEvent {
  final String fundCode;
  const RefreshDetail(this.fundCode);
  @override
  List<Object?> get props => [fundCode];
}

class LoadNavHistory extends DetailEvent {
  final String fundCode;
  final String period;
  const LoadNavHistory(this.fundCode, {this.period = '1y'});
  @override
  List<Object?> get props => [fundCode, period];
}
