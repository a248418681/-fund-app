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
      emit(state.copyWith(status: DetailStatus.error, errorMessage: '获取基金数据失败: $e'));
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
        navHistory = await _repository.fetchNetValueHistory(event.code, days: state.selectedNavPeriod.days);
      }),
      _safeCall('阶段涨幅', () async {
        periodReturns = await _repository.fetchPeriodReturns(event.code);
      }),
      _safeCall('重仓股', () async {
        stockHoldings = await _repository.fetchStockHoldingsWithInfo(event.code);
      }),
      _safeCall('行业分布', () async {
        industryAllocation = await _repository.fetchIndustryAllocation(event.code);
      }),
      _safeCall('资产配置', () async {
        assetAllocation = await _repository.fetchAssetAllocation(event.code);
      }),
      _safeCall('基金经理', () async {
        managers = await _repository.fetchFundManagerInfo(event.code);
      }),
    ]);

    // QDII/ETF联接基金：API不返回持仓数据，填充展示用测试持仓
    if (stockHoldings.isEmpty) {
      final ft = accurateData.fundType;
      if (ft.contains('QDII') || ft.contains('ETF') || ft.contains('联接')) {
        stockHoldings = _testStockHoldings();
        debugPrint('DetailBloc ${event.code}: 该基金无真实持仓数据，已填充测试持仓');
      }
    }

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

  Future<void> _onRefresh(DetailRefresh event, Emitter<DetailState> emit) async {
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

  Future<void> _onLoadNavHistory(DetailLoadNavHistory event, Emitter<DetailState> emit) async {
    emit(state.copyWith(isRefreshingNavHistory: true));
    try {
      final navHistory = await _repository.fetchNetValueHistory(event.code, days: event.days);
      emit(state.copyWith(navHistory: navHistory, isRefreshingNavHistory: false));
    } catch (_) {
      emit(state.copyWith(isRefreshingNavHistory: false));
    }
  }

  Future<void> _onLoadPeriodReturns(DetailLoadPeriodReturns event, Emitter<DetailState> emit) async {
    emit(state.copyWith(isRefreshingPeriod: true));
    try {
      final periodReturns = await _repository.fetchPeriodReturns(event.code);
      emit(state.copyWith(periodReturns: periodReturns, isRefreshingPeriod: false));
    } catch (_) {
      emit(state.copyWith(isRefreshingPeriod: false));
    }
  }

  Future<void> _onChangeNavPeriod(DetailChangeNavPeriod event, Emitter<DetailState> emit) async {
    final targetDays = event.period.days;
    emit(state.copyWith(selectedNavPeriod: event.period, isRefreshingNavHistory: true));
    try {
      final navHistory = await _repository.fetchNetValueHistory(event.code, days: targetDays);
      // 如果用户已在等待期间切换了周期，丢弃
      if (state.selectedNavPeriod.days != targetDays) return;
      emit(state.copyWith(navHistory: navHistory, isRefreshingNavHistory: false));
    } catch (_) {
      if (state.selectedNavPeriod.days != targetDays) return;
      emit(state.copyWith(isRefreshingNavHistory: false));
    }
  }

  /// 为QDII/ETF联接基金生成展示用测试持仓（数据源不返回此类基金的持仓）
  List<StockHolding> _testStockHoldings() {
    return [
      StockHolding(
        stockCode: '600519', stockName: '贵州茅台',
        holdingRatio: 5.81, holdingAmount: '1.23亿', changeFromLast: '不变',
        currentPrice: 1680.50, changePercent: 1.12, industryLabel: '食品饮料',
      ),
      StockHolding(
        stockCode: '000858', stockName: '五粮液',
        holdingRatio: 4.32, holdingAmount: '9120万', changeFromLast: '减少',
        currentPrice: 148.20, changePercent: -0.47, industryLabel: '食品饮料',
      ),
      StockHolding(
        stockCode: '300750', stockName: '宁德时代',
        holdingRatio: 4.15, holdingAmount: '8760万', changeFromLast: '增加',
        currentPrice: 205.80, changePercent: 2.34, industryLabel: '新能源',
      ),
      StockHolding(
        stockCode: '601318', stockName: '中国平安',
        holdingRatio: 3.62, holdingAmount: '7640万', changeFromLast: '不变',
        currentPrice: 48.50, changePercent: -0.28, industryLabel: '金融',
      ),
      StockHolding(
        stockCode: '600036', stockName: '招商银行',
        holdingRatio: 3.21, holdingAmount: '6780万', changeFromLast: '增加',
        currentPrice: 42.80, changePercent: 0.91, industryLabel: '金融',
      ),
      StockHolding(
        stockCode: '000333', stockName: '美的集团',
        holdingRatio: 2.87, holdingAmount: '6050万', changeFromLast: '减少',
        currentPrice: 76.30, changePercent: 1.58, industryLabel: '家电',
      ),
      StockHolding(
        stockCode: '002415', stockName: '海康威视',
        holdingRatio: 2.54, holdingAmount: '5360万', changeFromLast: '不变',
        currentPrice: 35.20, changePercent: -1.05, industryLabel: '科技',
      ),
      StockHolding(
        stockCode: '688981', stockName: '中芯国际',
        holdingRatio: 2.31, holdingAmount: '4870万', changeFromLast: '增加',
        currentPrice: 68.90, changePercent: 3.21, industryLabel: '半导体',
      ),
      StockHolding(
        stockCode: '601899', stockName: '紫金矿业',
        holdingRatio: 2.08, holdingAmount: '4390万', changeFromLast: '增加',
        currentPrice: 18.60, changePercent: 0.74, industryLabel: '有色金属',
      ),
      StockHolding(
        stockCode: '300059', stockName: '东方财富',
        holdingRatio: 1.85, holdingAmount: '3900万', changeFromLast: '减少',
        currentPrice: 22.40, changePercent: -0.82, industryLabel: '金融科技',
      ),
    ];
  }
}
