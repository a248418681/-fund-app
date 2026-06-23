import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import '../../../utils/error_util.dart';
import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final FundRepository _repository;

  HomeBloc(this._repository) : super(const HomeState()) {
    on<HomeInit>(_onInit);
    on<HomeRefresh>(_onRefresh);
    on<HomeAddWatchlist>(_onAddWatchlist);
    on<HomeRemoveWatchlist>(_onRemoveWatchlist);
    on<HomeChangeWatchlistSort>(_onChangeWatchlistSort);
  }

  Future<void> _onInit(HomeInit event, Emitter<HomeState> emit) async {
    emit(state.copyWith(status: HomeStatus.loading));
    try {
      // 并行：指数 + 自选列表 + 资讯（资讯失败了给空）
      final results = await Future.wait([
        _repository.fetchMarketIndices(),
        _repository.getWatchlist(),
        _repository
            .fetchFinanceNews(pageSize: 6)
            .then((v) => v, onError: (_) => <NewsItem>[]),
      ]);
      final indices = results[0] as List<MarketIndex>;
      final watchlistInfo = results[1] as List<FundInfo>;
      final news = results[2] as List<NewsItem>;

      final watchlist = await _buildWatchlistItems(watchlistInfo);

      emit(state.copyWith(
        status: HomeStatus.loaded,
        indices: indices,
        watchlist: watchlist,
        news: news,
        lastRefreshTime: _formatTime(DateTime.now()),
      ));
    } catch (e) {
      emit(state.copyWith(
          status: HomeStatus.error, errorMessage: ErrorUtil.format(e)));
    }
  }

  Future<void> _onRefresh(HomeRefresh event, Emitter<HomeState> emit) async {
    emit(state.copyWith(isRefreshing: true));
    try {
      // 并行：指数 + 自选列表 + 资讯
      final results = await Future.wait([
        _repository.fetchMarketIndices(),
        _repository.getWatchlist(),
        _repository
            .fetchFinanceNews(pageSize: 6)
            .then((v) => v, onError: (_) => state.news),
      ]);
      final indices = results[0] as List<MarketIndex>;
      final watchlistInfo = results[1] as List<FundInfo>;
      final news = results[2] as List<NewsItem>;

      final watchlist = await _buildWatchlistItems(watchlistInfo);

      emit(state.copyWith(
        indices: indices,
        watchlist: watchlist,
        news: news,
        lastRefreshTime: _formatTime(DateTime.now()),
        isRefreshing: false,
      ));
    } catch (e) {
      debugPrint('[HomeBloc] _onRefresh error: $e');
      emit(state.copyWith(
          isRefreshing: false, errorMessage: ErrorUtil.format(e)));
    }
  }

  Future<void> _onAddWatchlist(
      HomeAddWatchlist event, Emitter<HomeState> emit) async {
    await _repository.addToWatchlist(event.code, name: event.name);
    final watchlistInfo = await _repository.getWatchlist();
    final watchlist = await _buildWatchlistItems(watchlistInfo);
    emit(state.copyWith(watchlist: watchlist));
  }

  Future<void> _onRemoveWatchlist(
      HomeRemoveWatchlist event, Emitter<HomeState> emit) async {
    await _repository.removeFromWatchlist(event.code);
    final watchlist =
        state.watchlist.where((item) => item.code != event.code).toList();
    emit(state.copyWith(watchlist: watchlist));
  }

  void _onChangeWatchlistSort(
      HomeChangeWatchlistSort event, Emitter<HomeState> emit) {
    final newAsc = event.field == state.sortField ? !state.sortAsc : true;
    emit(state.copyWith(sortField: event.field, sortAsc: newAsc));
  }

  /// 用本地名称构建 WatchlistItem（估值数据只取数值，名称不依赖 API 解码）
  Future<List<WatchlistItem>> _buildWatchlistItems(
      List<FundInfo> watchlistInfo) async {
    if (watchlistInfo.isEmpty) return [];

    final codes = watchlistInfo.map((f) => f.code).toList();
    // 用 local 的 name 作为备用
    final nameMap = <String, String>{};
    for (final f in watchlistInfo) {
      nameMap[f.code] = f.name.isNotEmpty ? f.name : f.code;
    }

    // 获取估值
    Map<String, FundEstimate> estimates;
    try {
      estimates = await _repository.fetchFundEstimates(codes);
    } catch (e) {
      debugPrint('[HomeBloc] fetchFundEstimates error: $e');
      return codes
          .map((code) => WatchlistItem(
                code: code,
                name: nameMap[code] ?? code,
                loading: false,
                dataSource: 'estimate',
              ))
          .toList();
    }

    return codes.map((code) {
      final est = estimates[code];
      final name = nameMap[code] ?? code;
      if (est != null) {
        final safeValue = (est.gsz > 0)
            ? _safeToFixed(est.gsz, 4)
            : _safeToFixed(est.dwjz, 4);
        final safeLast = (est.dwjz > 0) ? _safeToFixed(est.dwjz, 4) : null;
        return WatchlistItem(
          code: code,
          name: name,
          estimateValue: safeValue,
          estimateChange: _safeToFixed(est.gszzl, 2),
          estimateTime: est.gztime,
          lastValue: safeLast,
          loading: false,
          dataSource: 'estimate',
        );
      }
      return WatchlistItem(
        code: code,
        name: name,
        loading: false,
        dataSource: 'estimate',
      );
    }).toList();
  }

  /// 安全格式化 double，防止 Infinity/NaN 导致 toStringAsFixed 抛异常
  String _safeToFixed(double value, int fractionDigits) {
    if (!value.isFinite) return '0.${'0' * fractionDigits}';
    return value.toStringAsFixed(fractionDigits);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
