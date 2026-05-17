import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum MarketStatus { initial, loading, loaded, error }

class MarketState extends Equatable {
  final MarketStatus status;
  final List<MarketIndex> indices;
  final List<FundRankItem> rankings;
  final List<SectorRankItem> sectors;
  final String sortType;
  final String order;
  final String fundType;
  final bool isRefreshing;
  final String? errorMessage;

  const MarketState({
    this.status = MarketStatus.initial,
    this.indices = const [],
    this.rankings = const [],
    this.sectors = const [],
    this.sortType = 'r',
    this.order = 'desc',
    this.fundType = 'all',
    this.isRefreshing = false,
    this.errorMessage,
  });

  MarketState copyWith({
    MarketStatus? status,
    List<MarketIndex>? indices,
    List<FundRankItem>? rankings,
    List<SectorRankItem>? sectors,
    String? sortType,
    String? order,
    String? fundType,
    bool? isRefreshing,
    String? errorMessage,
  }) {
    return MarketState(
      status: status ?? this.status,
      indices: indices ?? this.indices,
      rankings: rankings ?? this.rankings,
      sectors: sectors ?? this.sectors,
      sortType: sortType ?? this.sortType,
      order: order ?? this.order,
      fundType: fundType ?? this.fundType,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, indices, rankings, sectors, sortType, order, fundType, isRefreshing, errorMessage];
}
