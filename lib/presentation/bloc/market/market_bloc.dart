import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import 'market_event.dart';
import 'market_state.dart';

class MarketBloc extends Bloc<MarketEvent, MarketState> {
  final FundRepository _repository;
  int _fetchToken = 0;

  MarketBloc(this._repository) : super(const MarketState()) {
    on<MarketLoad>(_onLoad);
    on<MarketRefresh>(_onRefresh);
    on<MarketChangeSort>(_onChangeSort);
    on<MarketChangeFundType>(_onChangeFundType);
    on<MarketLoadSectors>(_onLoadSectors);
  }

  Future<void> _onLoad(MarketLoad event, Emitter<MarketState> emit) async {
    emit(state.copyWith(status: MarketStatus.loading));
    try {
      final indices = await _repository.fetchMarketIndices();
      var rankings = await _repository.fetchFundRanking(
        sortType: state.sortType,
        order: state.order,
        fundType: state.fundType,
      );
      rankings = _sortRankings(rankings, state.sortType, state.order);
      final sectors = await _repository.fetchSectorRanking(pageSize: 10);
      emit(state.copyWith(
        status: MarketStatus.loaded,
        indices: indices,
        rankings: rankings,
        sectors: sectors,
      ));
    } catch (e) {
      emit(state.copyWith(status: MarketStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> _onRefresh(MarketRefresh event, Emitter<MarketState> emit) async {
    final token = ++_fetchToken;
    emit(state.copyWith(isRefreshing: true));
    try {
      final indices = await _repository.fetchMarketIndices();
      if (token != _fetchToken) return;
      var rankings = await _repository.fetchFundRanking(
        sortType: state.sortType,
        order: state.order,
        fundType: state.fundType,
      );
      if (token != _fetchToken) return;
      rankings = _sortRankings(rankings, state.sortType, state.order);
      emit(state.copyWith(
        indices: indices,
        rankings: rankings,
        isRefreshing: false,
      ));
    } catch (e) {
      debugPrint('[MarketBloc] _onRefresh error: $e');
      if (token != _fetchToken) return;
      emit(state.copyWith(isRefreshing: false));
    }
  }

  Future<void> _onChangeSort(MarketChangeSort event, Emitter<MarketState> emit) async {
    final token = ++_fetchToken;
    emit(state.copyWith(sortType: event.sortType, order: event.order, isRefreshing: true));
    try {
      var rankings = await _repository.fetchFundRanking(
        sortType: event.sortType,
        order: event.order,
        fundType: state.fundType,
      );
      if (token != _fetchToken) return;
      rankings = _sortRankings(rankings, event.sortType, event.order);
      emit(state.copyWith(rankings: rankings, isRefreshing: false));
    } catch (e) {
      debugPrint('[MarketBloc] _onChangeSort error: $e');
      if (token != _fetchToken) return;
      emit(state.copyWith(isRefreshing: false));
    }
  }

  Future<void> _onChangeFundType(MarketChangeFundType event, Emitter<MarketState> emit) async {
    final token = ++_fetchToken;
    emit(state.copyWith(fundType: event.fundType, isRefreshing: true));
    try {
      var rankings = await _repository.fetchFundRanking(
        sortType: state.sortType,
        order: state.order,
        fundType: event.fundType,
      );
      if (token != _fetchToken) return;
      rankings = _sortRankings(rankings, state.sortType, state.order);
      emit(state.copyWith(rankings: rankings, isRefreshing: false));
    } catch (e) {
      debugPrint('[MarketBloc] _onChangeFundType error: $e');
      if (token != _fetchToken) return;
      emit(state.copyWith(isRefreshing: false));
    }
  }

  /// 客户端重排序：API 按基金类型分组排序，需要全局排序
  List<FundRankItem> _sortRankings(
    List<FundRankItem> items, String sortType, String order,
  ) {
    final sorted = List<FundRankItem>.from(items);
    sorted.sort((a, b) {
      double aVal, bVal;
      switch (sortType) {
        case 'r':    aVal = a.dayChange;        bVal = b.dayChange;        break;
        case 'zzf':  aVal = a.weekChange;       bVal = b.weekChange;       break;
        case '1yzf': aVal = a.monthChange;      bVal = b.monthChange;      break;
        case '3yzf': aVal = a.threeMonthChange; bVal = b.threeMonthChange; break;
        case '6yzf': aVal = a.halfYearChange;   bVal = b.halfYearChange;   break;
        case '1nzf': aVal = a.yearChange;       bVal = b.yearChange;       break;
        default:     aVal = a.dayChange;        bVal = b.dayChange;
      }
      return order == 'desc' ? bVal.compareTo(aVal) : aVal.compareTo(bVal);
    });
    return sorted;
  }

  Future<void> _onLoadSectors(MarketLoadSectors event, Emitter<MarketState> emit) async {
    try {
      final sectors = await _repository.fetchSectorRanking(pageSize: 10);
      emit(state.copyWith(sectors: sectors));
    } catch (e) {
      debugPrint('[MarketBloc] _onLoadSectors error: $e');
    }
  }
}
