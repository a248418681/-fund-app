import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum SearchStatus { initial, loading, loaded, error }

class SearchState extends Equatable {
  final SearchStatus status;
  final String query;
  final List<FundInfo> results;
  final List<FundInfo> hotFunds;
  final String? errorMessage;
  final FundInfo? selected;

  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.results = const [],
    this.hotFunds = const [],
    this.errorMessage,
    this.selected,
  });

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<FundInfo>? results,
    List<FundInfo>? hotFunds,
    String? errorMessage,
    FundInfo? selected,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      results: results ?? this.results,
      hotFunds: hotFunds ?? this.hotFunds,
      errorMessage: errorMessage ?? this.errorMessage,
      selected: selected ?? this.selected,
    );
  }

  @override
  List<Object?> get props =>
      [status, query, results, hotFunds, errorMessage, selected];
}
