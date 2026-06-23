import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import 'market_event.dart';
import 'market_state.dart';

class MarketBloc extends Bloc<MarketEvent, MarketState> {
  final FundRepository _repository;
  int _fetchToken = 0;

  static const _topN = 20;

  MarketBloc(this._repository) : super(const MarketState()) {
    on<MarketLoad>(_onLoad);
    on<MarketRefresh>(_onRefresh);
    on<MarketChangeTab>(_onChangeTab);
    on<MarketChangeSort>(_onChangeSort);
    on<MarketLoadSectors>(_onLoadSectors);
  }

  /// 分两次请求涨幅/跌幅 TopN（避免拉取 20000 条全量数据）
  Future<({List<FundRankItem> gainers, List<FundRankItem> losers})>
      _fetchGainersAndLosers(
    String sortType, {
    bool forceRefresh = false,
  }) async {
    // 涨幅榜：按日涨幅降序取前 TopN
    final gainers = await _repository.fetchFundRanking(
      sortType: sortType,
      order: 'desc',
      pageSize: _topN,
      fundType: 'all',
    );

    // 跌幅榜：按日涨幅升序取前 TopN
    final losersRaw = await _repository.fetchFundRanking(
      sortType: sortType,
      order: 'asc',
      pageSize: _topN,
      fundType: 'all',
    );
    // 过滤掉 dayChange >= 0 的（升序可能混入 0 或正值）
    final losers = losersRaw.where((item) => item.dayChange < 0).toList();

    return (gainers: gainers, losers: losers);
  }

  Future<void> _onLoad(MarketLoad event, Emitter<MarketState> emit) async {
    emit(state.copyWith(status: MarketStatus.loading));
    try {
      // Phase 1: 指数 + 板块先到（~500ms），立即上屏
      final phase1 = await Future.wait([
        _repository.fetchMarketIndices(),
        _repository.fetchSectorRanking(pageSize: 10),
      ]);
      emit(state.copyWith(
        status: MarketStatus.loaded,
        indices: phase1[0] as List<MarketIndex>,
        sectors: phase1[1] as List<SectorRankItem>,
      ));

      // Phase 2: 排行榜后到（全量缓存未命中时 ~2-3s），增量更新
      final rankResult =
          await _fetchGainersAndLosers(state.sortType, forceRefresh: true);
      emit(state.copyWith(
        gainers: rankResult.gainers,
        losers: rankResult.losers,
      ));
    } catch (e) {
      emit(state.copyWith(
          status: MarketStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> _onRefresh(
      MarketRefresh event, Emitter<MarketState> emit) async {
    final token = ++_fetchToken;
    emit(state.copyWith(isRefreshing: true));
    try {
      final results = await Future.wait([
        _repository.fetchMarketIndices(),
        _fetchGainersAndLosers(state.sortType, forceRefresh: true),
      ]);
      if (token != _fetchToken) return;
      final rankResult = results[1] as ({
        List<FundRankItem> gainers,
        List<FundRankItem> losers
      });
      emit(state.copyWith(
        indices: results[0] as List<MarketIndex>,
        gainers: rankResult.gainers,
        losers: rankResult.losers,
        isRefreshing: false,
      ));
    } catch (e) {
      debugPrint('[MarketBloc] _onRefresh error: $e');
      if (token != _fetchToken) return;
      emit(state.copyWith(isRefreshing: false));
    }
  }

  void _onChangeTab(MarketChangeTab event, Emitter<MarketState> emit) {
    emit(state.copyWith(tabIndex: event.tabIndex));
  }

  Future<void> _onChangeSort(
      MarketChangeSort event, Emitter<MarketState> emit) async {
    final token = ++_fetchToken;
    emit(state.copyWith(sortType: event.sortType, isRefreshing: true));
    try {
      final rankResult = await _fetchGainersAndLosers(event.sortType);
      if (token != _fetchToken) return;
      emit(state.copyWith(
        gainers: rankResult.gainers,
        losers: rankResult.losers,
        isRefreshing: false,
      ));
    } catch (e) {
      debugPrint('[MarketBloc] _onChangeSort error: $e');
      if (token != _fetchToken) return;
      emit(state.copyWith(isRefreshing: false));
    }
  }

  Future<void> _onLoadSectors(
      MarketLoadSectors event, Emitter<MarketState> emit) async {
    try {
      final sectors = await _repository.fetchSectorRanking(pageSize: 10);
      emit(state.copyWith(sectors: sectors));
    } catch (e) {
      debugPrint('[MarketBloc] _onLoadSectors error: $e');
    }
  }
}
