import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();
  @override
  List<Object?> get props => [];
}

class SearchQueryChanged extends SearchEvent {
  final String query;
  const SearchQueryChanged(this.query);
  @override
  List<Object?> get props => [query];
}

class SearchCleared extends SearchEvent {
  const SearchCleared();
}

class SearchFundSelected extends SearchEvent {
  final String code;
  final String name;
  const SearchFundSelected({required this.code, required this.name});
  @override
  List<Object?> get props => [code, name];
}
