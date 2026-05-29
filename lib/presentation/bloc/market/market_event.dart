import 'package:equatable/equatable.dart';

abstract class MarketEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class MarketLoad extends MarketEvent {}

class MarketRefresh extends MarketEvent {}

class MarketChangeTab extends MarketEvent {
  final int tabIndex; // 0=涨幅榜, 1=跌幅榜
  MarketChangeTab(this.tabIndex);
  @override
  List<Object?> get props => [tabIndex];
}

class MarketChangeSort extends MarketEvent {
  final String sortType; // r=日, zzf=周, 1yzf=月, 3yzf=三月, 6yzf=半年, 1nzf=年
  MarketChangeSort(this.sortType);
  @override
  List<Object?> get props => [sortType];
}

class MarketLoadSectors extends MarketEvent {}
