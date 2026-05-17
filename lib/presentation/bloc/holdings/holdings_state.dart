import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum HoldingsStatus { initial, loading, loaded, error }

enum HoldingsSortField { name, marketValue, estimateChange, netValueChange, todayProfit, totalProfit }

class HoldingsState extends Equatable {
  final HoldingsStatus status;
  final List<HoldingWithProfit> holdings;
  final HoldingSummary summary;
  final bool isRefreshing;
  final String? errorMessage;
  final DateTime? lastRefreshTime;
  final HoldingsSortField sortField;
  final bool sortAsc;

  HoldingsState({
    this.status = HoldingsStatus.initial,
    this.holdings = const [],
    HoldingSummary? summary,
    this.isRefreshing = false,
    this.errorMessage,
    this.lastRefreshTime,
    this.sortField = HoldingsSortField.name,
    this.sortAsc = true,
  }) : summary = summary ?? HoldingSummary(
    totalValue: 0,
    totalCost: 0,
    totalProfit: 0,
    totalProfitRate: 0,
    todayProfit: 0,
  );

  HoldingsState copyWith({
    HoldingsStatus? status,
    List<HoldingWithProfit>? holdings,
    HoldingSummary? summary,
    bool? isRefreshing,
    String? errorMessage,
    DateTime? lastRefreshTime,
    HoldingsSortField? sortField,
    bool? sortAsc,
  }) {
    return HoldingsState(
      status: status ?? this.status,
      holdings: holdings ?? this.holdings,
      summary: summary ?? this.summary,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: errorMessage ?? this.errorMessage,
      lastRefreshTime: lastRefreshTime ?? this.lastRefreshTime,
      sortField: sortField ?? this.sortField,
      sortAsc: sortAsc ?? this.sortAsc,
    );
  }

  List<HoldingWithProfit> get sortedHoldings {
    final list = [...holdings];
    list.sort((a, b) {
      int cmp;
      switch (sortField) {
        case HoldingsSortField.name:
          cmp = (a.name.isNotEmpty ? a.name : a.code)
              .compareTo(b.name.isNotEmpty ? b.name : b.code);
        case HoldingsSortField.marketValue:
          cmp = (a.marketValue).compareTo(b.marketValue);
        case HoldingsSortField.estimateChange:
          cmp = (a.estimateChange ?? 0).compareTo(b.estimateChange ?? 0);
        case HoldingsSortField.netValueChange:
          final ad = double.tryParse(a.todayChange) ?? 0;
          final bd = double.tryParse(b.todayChange) ?? 0;
          cmp = ad.compareTo(bd);
        case HoldingsSortField.todayProfit:
          cmp = a.todayProfit.compareTo(b.todayProfit);
        case HoldingsSortField.totalProfit:
          cmp = a.profit.compareTo(b.profit);
      }
      return sortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  List<Object?> get props => [status, holdings, summary, isRefreshing, errorMessage, lastRefreshTime, sortField, sortAsc];
}
