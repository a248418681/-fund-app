import 'package:equatable/equatable.dart';

abstract class MarketEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class MarketLoad extends MarketEvent {}

class MarketRefresh extends MarketEvent {}

class MarketChangeSort extends MarketEvent {
  final String sortType;
  final String order;
  MarketChangeSort(this.sortType, this.order);
  @override
  List<Object?> get props => [sortType, order];
}

class MarketChangeFundType extends MarketEvent {
  final String fundType;
  MarketChangeFundType(this.fundType);
  @override
  List<Object?> get props => [fundType];
}

class MarketLoadSectors extends MarketEvent {}
