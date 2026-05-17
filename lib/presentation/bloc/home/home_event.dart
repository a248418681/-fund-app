import 'package:equatable/equatable.dart';
import 'home_state.dart';

abstract class HomeEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class HomeInit extends HomeEvent {}

class HomeRefresh extends HomeEvent {}

class HomeAddWatchlist extends HomeEvent {
  final String code;
  final String name;
  HomeAddWatchlist(this.code, this.name);
  @override
  List<Object?> get props => [code, name];
}

class HomeRemoveWatchlist extends HomeEvent {
  final String code;
  HomeRemoveWatchlist(this.code);
  @override
  List<Object?> get props => [code];
}

class HomeLoadWatchlistEstimates extends HomeEvent {}

class HomeChangeWatchlistSort extends HomeEvent {
  final WatchlistSortField field;
  HomeChangeWatchlistSort(this.field);
  @override
  List<Object?> get props => [field];
}
