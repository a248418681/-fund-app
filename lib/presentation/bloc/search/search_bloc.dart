import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import '../../../utils/error_util.dart';
import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final FundRepository _repository;
  int _requestId = 0;
  CancelToken? _cancelToken;

  SearchBloc(this._repository) : super(const SearchState()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchCleared>(_onCleared);
    on<SearchFundSelected>(_onFundSelected);

    // 初始化热门基金
    add(const SearchQueryChanged(''));
  }

  Future<void> _onQueryChanged(
      SearchQueryChanged event, Emitter<SearchState> emit) async {
    final query = event.query.trim();

    // 空查询显示热门基金
    if (query.isEmpty) {
      _requestId = 0; // 重置，确保后续非空查询不被旧 id 误杀
      emit(state.copyWith(
        status: SearchStatus.loaded,
        query: '',
        results: state.hotFunds.isEmpty ? _defaultHotFunds : state.hotFunds,
      ));
      return;
    }

    // 取消上一次飞行中的请求
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    final myId = ++_requestId;
    final myCancelToken = _cancelToken;
    emit(state.copyWith(status: SearchStatus.loading, query: query));

    // 防抖 300ms
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (myId != _requestId) return;

    try {
      final results =
          await _repository.searchFund(query, cancelToken: myCancelToken);
      if (myId != _requestId) return;

      // 缓存热门基金
      final hotFunds =
          state.hotFunds.isEmpty ? results.take(20).toList() : state.hotFunds;

      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: results,
        hotFunds: hotFunds,
      ));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return; // 主动取消，不报错
      if (myId != _requestId) return;
      emit(state.copyWith(
        status: SearchStatus.error,
        errorMessage: '搜索失败，请检查网络',
      ));
    } catch (e) {
      if (myId != _requestId) return;
      emit(state.copyWith(
        status: SearchStatus.error,
        errorMessage: ErrorUtil.format(e),
      ));
    }
  }

  Future<void> _onCleared(
      SearchCleared event, Emitter<SearchState> emit) async {
    _requestId = 0;
    emit(state.copyWith(
      status: SearchStatus.loaded,
      query: '',
      results: state.hotFunds,
    ));
  }

  void _onFundSelected(SearchFundSelected event, Emitter<SearchState> emit) {
    final fund = state.results.firstWhere(
      (f) => f.code == event.code,
      orElse: () =>
          FundInfo(code: event.code, name: event.name, type: '', pinyin: ''),
    );
    emit(state.copyWith(selected: fund));
  }

  /// 默认热门基金列表（搜索为空时展示）
  static final List<FundInfo> _defaultHotFunds = [
    FundInfo(
        code: '005827', name: '易方达蓝筹精选混合', type: '混合型', pinyin: 'yifangda'),
    FundInfo(
        code: '110022',
        name: '招商中证白酒指数(LOF)A',
        type: '指数型',
        pinyin: 'zhaoshang'),
    FundInfo(
        code: '012348',
        name: '天弘恒生科技指数(QDII)C',
        type: 'QDII',
        pinyin: 'tianhong'),
    FundInfo(
        code: '001548',
        name: '招商国证生物医药指数(LOF)',
        type: '指数型',
        pinyin: 'zhaoshang'),
    FundInfo(code: '320007', name: '诺安成长混合', type: '混合型', pinyin: 'nuoan'),
    FundInfo(
        code: '162703', name: '广发中证传媒ETF联接A', type: '指数型', pinyin: 'guangfa'),
    FundInfo(
        code: '006328', name: '中泰星元灵活配置混合A', type: '混合型', pinyin: 'zhongtai'),
    FundInfo(
        code: '000961', name: '天弘沪深300ETF联接A', type: '指数型', pinyin: 'tianhong'),
    FundInfo(
        code: '159915', name: '易方达创业板ETF', type: '指数型', pinyin: 'yifangda'),
    FundInfo(
        code: '513500', name: '博时标普500ETF联接A', type: 'QDII', pinyin: 'bosera'),
  ];

  @override
  Future<void> close() {
    _requestId = 0;
    _cancelToken?.cancel();
    return super.close();
  }
}
