import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/fund_repository.dart';
import '../../../domain/entities/fund_entity.dart';
import 'detail_event.dart';
import 'detail_state.dart';

class DetailBloc extends Bloc<DetailEvent, DetailState> {
  final FundRepository _repository;

  DetailBloc(this._repository) : super(const DetailState()) {
    on<DetailLoad>(_onLoad);
    on<DetailRefresh>(_onRefresh);
    on<DetailLoadNavHistory>(_onLoadNavHistory);
    on<DetailLoadPeriodReturns>(_onLoadPeriodReturns);
    on<DetailChangeNavPeriod>(_onChangeNavPeriod);
  }

  Future<void> _onLoad(DetailLoad event, Emitter<DetailState> emit) async {
    emit(state.copyWith(status: DetailStatus.loading));

    // 关键数据：基金估值/净值 — 必须成功才显示页面
    FundAccurateData? accurateData;
    try {
      accurateData = await _repository.fetchFundAccurateData(event.code);
    } catch (e) {
      debugPrint('DetailBloc 核心数据加载失败：$e');
      emit(state.copyWith(
          status: DetailStatus.error, errorMessage: '获取基金数据失败: $e'));
      return;
    }

    // 非关键数据：每个独立请求，失败不阻断页面
    List<NetValueRecord> navHistory = [];
    List<PeriodReturn> periodReturns = [];
    List<StockHolding> stockHoldings = [];
    List<IndustryAllocation> industryAllocation = [];
    AssetAllocation? assetAllocation;
    List<FundManagerInfo> managers = [];

    await Future.wait([
      _safeCall('净值历史', () async {
        navHistory = await _repository.fetchNetValueHistory(event.code,
            days: state.selectedNavPeriod.days);
      }),
      _safeCall('阶段涨幅', () async {
        periodReturns = await _repository.fetchPeriodReturns(event.code);
      }),
      _safeCall('重仓股', () async {
        stockHoldings =
            await _repository.fetchStockHoldingsWithInfo(event.code);
      }),
      _safeCall('行业分布', () async {
        industryAllocation =
            await _repository.fetchIndustryAllocation(event.code);
      }),
      _safeCall('资产配置', () async {
        assetAllocation = await _repository.fetchAssetAllocation(event.code);
      }),
      _safeCall('基金经理', () async {
        managers = await _repository.fetchFundManagerInfo(event.code);
      }),
    ]);

    // QDII/ETF联接基金：API不返回持仓数据，显示空列表
    // （移除硬编码测试持仓，前端可显示"暂不支持持仓穿透"提示）

    emit(state.copyWith(
      status: DetailStatus.loaded,
      accurateData: accurateData,
      navHistory: navHistory,
      periodReturns: periodReturns,
      stockHoldings: stockHoldings,
      industryAllocation: industryAllocation,
      assetAllocation: assetAllocation,
      managers: managers,
    ));
  }

  /// 非关键 API 调用保护：失败只打日志，不抛异常
  Future<void> _safeCall(String label, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      debugPrint('DetailBloc [$label] 获取失败（非致命）：$e');
    }
  }

  Future<void> _onRefresh(
      DetailRefresh event, Emitter<DetailState> emit) async {
    try {
      final accurateData = await _repository.fetchFundAccurateData(event.code);
      emit(state.copyWith(
        accurateData: accurateData,
        navHistory: state.navHistory,
        periodReturns: state.periodReturns,
      ));
    } catch (e) {
      debugPrint('DetailBloc 刷新失败（保留旧数据）：$e');
    }
  }

  Future<void> _onLoadNavHistory(
      DetailLoadNavHistory event, Emitter<DetailState> emit) async {
    emit(state.copyWith(isRefreshingNavHistory: true));
    try {
      final navHistory =
          await _repository.fetchNetValueHistory(event.code, days: event.days);
      emit(state.copyWith(
          navHistory: navHistory, isRefreshingNavHistory: false));
    } catch (_) {
      emit(state.copyWith(isRefreshingNavHistory: false));
    }
  }

  Future<void> _onLoadPeriodReturns(
      DetailLoadPeriodReturns event, Emitter<DetailState> emit) async {
    emit(state.copyWith(isRefreshingPeriod: true));
    try {
      final periodReturns = await _repository.fetchPeriodReturns(event.code);
      emit(state.copyWith(
          periodReturns: periodReturns, isRefreshingPeriod: false));
    } catch (_) {
      emit(state.copyWith(isRefreshingPeriod: false));
    }
  }

  Future<void> _onChangeNavPeriod(
      DetailChangeNavPeriod event, Emitter<DetailState> emit) async {
    final targetDays = event.period.days;
    emit(state.copyWith(
        selectedNavPeriod: event.period, isRefreshingNavHistory: true));
    try {
      final navHistory =
          await _repository.fetchNetValueHistory(event.code, days: targetDays);
      // 如果用户已在等待期间切换了周期，丢弃
      if (state.selectedNavPeriod.days != targetDays) return;
      emit(state.copyWith(
          navHistory: navHistory, isRefreshingNavHistory: false));
    } catch (_) {
      if (state.selectedNavPeriod.days != targetDays) return;
      emit(state.copyWith(isRefreshingNavHistory: false));
    }
  }
}
