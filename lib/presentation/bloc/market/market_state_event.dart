import 'package:equatable/equatable.dart';
import '../../../../data/models/fund_model.dart';

class MarketState extends Equatable {
  final List<FundInfo> funds;
  final bool isLoading;
  final String? error;

  const MarketState({
    this.funds = const [],
    this.isLoading = false,
    this.error,
  });

  @override
  List<Object?> get props => [funds, isLoading, error];

  MarketState copyWith(
      {List<FundInfo>? funds, bool? isLoading, String? error}) {
    return MarketState(
      funds: funds ?? this.funds,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

abstract class MarketEvent extends Equatable {
  const MarketEvent();
  @override
  List<Object?> get props => [];
}

class LoadMarketList extends MarketEvent {
  final String type;
  const LoadMarketList(this.type);
  @override
  List<Object?> get props => [type];
}
