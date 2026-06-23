import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum HomeStatus { initial, loading, loaded, error }

enum WatchlistSortField { name, estimateValue, estimateChange }

class HomeState extends Equatable {
  final HomeStatus status;
  final List<MarketIndex> indices;
  final List<WatchlistItem> watchlist;
  final List<NewsItem> news;
  final String? errorMessage;
  final String lastRefreshTime;
  final bool isRefreshing;
  final WatchlistSortField sortField;
  final bool sortAsc;

  const HomeState({
    this.status = HomeStatus.initial,
    this.indices = const [],
    this.watchlist = const [],
    this.news = const [],
    this.errorMessage,
    this.lastRefreshTime = '',
    this.isRefreshing = false,
    this.sortField = WatchlistSortField.name,
    this.sortAsc = true,
  });

  HomeState copyWith({
    HomeStatus? status,
    List<MarketIndex>? indices,
    List<WatchlistItem>? watchlist,
    List<NewsItem>? news,
    String? errorMessage,
    String? lastRefreshTime,
    bool? isRefreshing,
    WatchlistSortField? sortField,
    bool? sortAsc,
  }) {
    return HomeState(
      status: status ?? this.status,
      indices: indices ?? this.indices,
      watchlist: watchlist ?? this.watchlist,
      news: news ?? this.news,
      errorMessage: errorMessage ?? this.errorMessage,
      lastRefreshTime: lastRefreshTime ?? this.lastRefreshTime,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      sortField: sortField ?? this.sortField,
      sortAsc: sortAsc ?? this.sortAsc,
    );
  }

  List<WatchlistItem> get sortedWatchlist {
    final list = [...watchlist];
    list.sort((a, b) {
      int cmp;
      switch (sortField) {
        case WatchlistSortField.name:
          cmp = (a.name.isNotEmpty ? a.name : a.code)
              .compareTo(b.name.isNotEmpty ? b.name : b.code);
        case WatchlistSortField.estimateValue:
          final av = double.tryParse(a.estimateValue ?? '0') ?? 0;
          final bv = double.tryParse(b.estimateValue ?? '0') ?? 0;
          cmp = av.compareTo(bv);
        case WatchlistSortField.estimateChange:
          final ac = double.tryParse(a.estimateChange ?? '0') ?? 0;
          final bc = double.tryParse(b.estimateChange ?? '0') ?? 0;
          cmp = ac.compareTo(bc);
      }
      return sortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  List<Object?> get props => [
        status,
        indices,
        watchlist,
        news,
        errorMessage,
        lastRefreshTime,
        isRefreshing,
        sortField,
        sortAsc
      ];
}
