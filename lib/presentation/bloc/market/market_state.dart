import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum MarketStatus { initial, loading, loaded, error }

class MarketState extends Equatable {
  final MarketStatus status;
  final List<MarketIndex> indices;
  final List<FundRankItem> gainers; // 涨幅 Top20（经客户端重排序）
  final List<FundRankItem> losers; // 跌幅 Top20（经客户端重排序）
  final List<SectorRankItem> sectors;
  final int tabIndex; // 0=涨幅榜, 1=跌幅榜
  final String sortType; // r/zzf/1yzf/3yzf/6yzf/1nzf
  final bool isRefreshing;
  final String? errorMessage;

  const MarketState({
    this.status = MarketStatus.initial,
    this.indices = const [],
    this.gainers = const [],
    this.losers = const [],
    this.sectors = const [],
    this.tabIndex = 0,
    this.sortType = 'r',
    this.isRefreshing = false,
    this.errorMessage,
  });

  MarketState copyWith({
    MarketStatus? status,
    List<MarketIndex>? indices,
    List<FundRankItem>? gainers,
    List<FundRankItem>? losers,
    List<SectorRankItem>? sectors,
    int? tabIndex,
    String? sortType,
    bool? isRefreshing,
    String? errorMessage,
  }) {
    return MarketState(
      status: status ?? this.status,
      indices: indices ?? this.indices,
      gainers: gainers ?? this.gainers,
      losers: losers ?? this.losers,
      sectors: sectors ?? this.sectors,
      tabIndex: tabIndex ?? this.tabIndex,
      sortType: sortType ?? this.sortType,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        indices,
        gainers,
        losers,
        sectors,
        tabIndex,
        sortType,
        isRefreshing,
        errorMessage
      ];
}
