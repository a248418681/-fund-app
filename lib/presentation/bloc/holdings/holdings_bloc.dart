import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/trading_calendar.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import 'holdings_event.dart';
import 'holdings_state.dart';

class HoldingsBloc extends Bloc<HoldingsEvent, HoldingsState> {
  final FundRepository _repository;
  Timer? _autoRefreshTimer;

  HoldingsBloc(this._repository) : super(HoldingsState()) {
    on<HoldingsLoad>(_onLoad);
    on<HoldingsRefresh>(_onRefresh);
    on<HoldingsSilentRefresh>(_onSilentRefresh);
    on<HoldingsAdd>(_onAdd);
    on<HoldingsUpdate>(_onUpdate);
    on<HoldingsDelete>(_onDelete);
    on<HoldingsAutoRefreshTick>(_onAutoRefreshTick);
    on<HoldingsChangeSort>(_onChangeSort);
  }

  /// 启动交易时间自动刷新（每 60 秒）
  void startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => add(HoldingsAutoRefreshTick()),
    );
    debugPrint('[Holdings] 自动刷新已启动（60s）');
  }

  /// 停止自动刷新
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// 当前是否在交易时间（9:30-15:00 连续，含午休）
  /// 午休期间估值仍有参考价值，应触发刷新并显示"当日估算涨跌"
  static bool isInTradingTime() => TradingCalendar.isMarketOpen();

  @override
  Future<void> close() {
    _autoRefreshTimer?.cancel();
    return super.close();
  }

  Future<void> _onLoad(HoldingsLoad event, Emitter<HoldingsState> emit) async {
    emit(state.copyWith(status: HoldingsStatus.loading));
    try {
      final records = await _repository.getHoldings();
      final enriched = await _enrichAll(records);
      final summary = _calcSummary(enriched);
      emit(state.copyWith(
        status: HoldingsStatus.loaded,
        holdings: enriched,
        summary: summary,
        lastRefreshTime: DateTime.now(),
      ));
    } catch (e) {
      emit(state.copyWith(
          status: HoldingsStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> _onRefresh(
      HoldingsRefresh event, Emitter<HoldingsState> emit) async {
    emit(state.copyWith(isRefreshing: true));
    try {
      final records = await _repository.getHoldings();
      final enriched = await _enrichAll(records);
      final summary = _calcSummary(enriched);
      emit(state.copyWith(
        status: HoldingsStatus.loaded,
        holdings: enriched,
        summary: summary,
        isRefreshing: false,
        lastRefreshTime: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('[Holdings] 刷新失败: $e');
      emit(state.copyWith(isRefreshing: false));
    }
  }

  /// 静默刷新：不设 isRefreshing，只有数据真的变了才 emit
  Future<void> _onSilentRefresh(
      HoldingsSilentRefresh event, Emitter<HoldingsState> emit) async {
    try {
      final records = await _repository.getHoldings();
      final enriched = await _enrichAll(records);
      // Diff：比较关键字段，无变化不 emit（避免 UI 闪烁）
      if (_holdingsChanged(state.holdings, enriched)) {
        final summary = _calcSummary(enriched);
        emit(state.copyWith(
          holdings: enriched,
          summary: summary,
          lastRefreshTime: DateTime.now(),
        ));
        debugPrint('[Holdings] 静默刷新：数据有更新');
      } else {
        debugPrint('[Holdings] 静默刷新：数据无变化');
      }
    } catch (e) {
      debugPrint('[Holdings] 静默刷新失败: $e');
      // 静默刷新失败不影响 UI
    }
  }

  /// 自动刷新 tick：仅在交易时间触发静默刷新
  Future<void> _onAutoRefreshTick(
      HoldingsAutoRefreshTick event, Emitter<HoldingsState> emit) async {
    if (!isInTradingTime()) return;
    if (state.status != HoldingsStatus.loaded) return;
    await _onSilentRefresh(HoldingsSilentRefresh(), emit);
  }

  /// 切换排序：同字段切换升降序，不同字段默认升序
  void _onChangeSort(HoldingsChangeSort event, Emitter<HoldingsState> emit) {
    final newAsc = event.field == state.sortField ? !state.sortAsc : true;
    emit(state.copyWith(sortField: event.field, sortAsc: newAsc));
  }

  /// 比较持仓数据是否有实质变化（忽略浮点精度差异）
  bool _holdingsChanged(
      List<HoldingWithProfit> old, List<HoldingWithProfit> cur) {
    if (old.length != cur.length) return true;
    for (var i = 0; i < old.length; i++) {
      final a = old[i];
      final b = cur[i];
      if (a.code != b.code ||
          a.marketValue != b.marketValue ||
          a.todayProfit != b.todayProfit ||
          a.todayChange != b.todayChange ||
          a.nav != b.nav ||
          a.navUpdated != b.navUpdated ||
          a.hasError != b.hasError ||
          a.changeLabel != b.changeLabel ||
          a.estimateChange != b.estimateChange ||
          a.estimateTime != b.estimateTime) {
        return true;
      }
    }
    return false;
  }

  Future<void> _onAdd(HoldingsAdd event, Emitter<HoldingsState> emit) async {
    await _repository.addOrUpdateHolding(event.holding);
    final records = await _repository.getHoldings();
    final enriched = await _enrichAll(records);
    emit(state.copyWith(holdings: enriched, summary: _calcSummary(enriched)));
  }

  Future<void> _onUpdate(
      HoldingsUpdate event, Emitter<HoldingsState> emit) async {
    await _repository.addOrUpdateHolding(event.holding);
    final records = await _repository.getHoldings();
    final enriched = await _enrichAll(records);
    emit(state.copyWith(holdings: enriched, summary: _calcSummary(enriched)));
  }

  Future<void> _onDelete(
      HoldingsDelete event, Emitter<HoldingsState> emit) async {
    await _repository.removeHolding(event.code);
    final records = await _repository.getHoldings();
    final enriched = await _enrichAll(records);
    emit(state.copyWith(holdings: enriched, summary: _calcSummary(enriched)));
  }

  /// 并发丰富所有持仓的实时数据（限制并发数防止触发 API 限流）
  Future<List<HoldingWithProfit>> _enrichAll(
      List<HoldingRecord> records) async {
    if (records.isEmpty) return [];
    final results = <HoldingWithProfit>[];
    // 分批：每批最多 5 个并发
    for (var i = 0; i < records.length; i += 5) {
      final batch = records.skip(i).take(5).map(_enrichOne);
      results.addAll(await Future.wait(batch));
    }
    return results;
  }

  Future<HoldingWithProfit> _enrichOne(HoldingRecord h) async {
    double currentNav = h.buyNetValue;
    double currentValue = h.amount;
    double dayChangePct = 0;
    double estChange = 0; // 今日预估涨跌幅
    String dataSource = 'nav';
    String navDate = '';
    String estimateTime = '';
    bool hasError = false;
    // effectiveShares 只算一次，下方 todayProfit 复用
    double effectiveShares = h.shares;

    try {
      final data = await _repository.fetchFundAccurateData(h.code);
      if (data.nav > 0) {
        currentNav = data.nav;
      }
      effectiveShares = h.shares > 0
          ? h.shares
          : (currentNav > 0 ? h.amount / currentNav : h.amount);
      currentValue = effectiveShares * currentNav;
      dayChangePct = data.dayChange;
      estChange = data.estimateChange;
      dataSource = data.dataSource;
      navDate = data.navDate;
      estimateTime = data.estimateTime;
      // 降级数据源(pz-only/danjuan)不算错误，只是精度降低
      // hasError 仅在 catch 中设置
    } catch (e) {
      hasError = true;
      debugPrint('[Holdings] 获取净值失败 ${h.code}(${h.name}): $e');
    }

    final now = DateTime.now();
    final today = _formatDate(now);
    final isTradingDay = TradingCalendar.isTradingDay(now);
    final isTradingTime = isTradingDay && TradingCalendar.isMarketOpen(now);
    final hour = now.hour;
    final minute = now.minute;
    final navUpdated = navDate == today;

    // 今日收益
    double todayProfit = 0;
    if (dayChangePct != 0 && dayChangePct.abs() < 20) {
      final prevNav = currentNav / (1 + dayChangePct / 100);
      todayProfit = effectiveShares * (currentNav - prevNav);
    }

    final profit = currentValue - h.amount;
    final profitRate = h.amount > 0 ? profit / h.amount : 0.0;

    // 根据时间动态生成标签
    String changeLabel;
    String changeUpdateTime;

    if (!isTradingDay) {
      // 非交易日：显示"上一交易日涨跌"
      changeLabel = '上一交易日涨跌';
      changeUpdateTime = navDate.isNotEmpty ? '$navDate净值' : '';
    } else if (hour < 9 || (hour == 9 && minute < 30)) {
      // 交易日开盘前：显示"昨日涨跌"
      changeLabel = '昨日涨跌';
      changeUpdateTime = navDate.isNotEmpty ? '$navDate净值' : '';
    } else if (isTradingTime) {
      // 交易时间内：显示"当日估算涨跌"
      changeLabel = '当日估算涨跌';
      changeUpdateTime = estimateTime.isNotEmpty ? '$estimateTime更新' : '';
    } else if (hour >= 15 && hour < 20 && !navUpdated) {
      // 收盘后到晚上8点，净值未更新：显示"当日估算涨跌（待更新）"
      changeLabel = '当日估算涨跌';
      changeUpdateTime =
          estimateTime.isNotEmpty ? '$estimateTime（待净值更新）' : '待净值更新';
    } else if (navUpdated) {
      // 净值已更新：显示"当日涨跌"
      changeLabel = '当日涨跌';
      changeUpdateTime = '$navDate净值';
    } else {
      // 其他情况：显示"上一交易日涨跌"
      changeLabel = '上一交易日涨跌';
      changeUpdateTime = navDate.isNotEmpty ? '$navDate净值' : '';
    }

    return HoldingWithProfit(
      code: h.code,
      name: h.name,
      fundType: h.fundType,
      shareClass: h.shareClass,
      amount: h.amount,
      buyNetValue: h.buyNetValue,
      shares: h.shares,
      buyDate: h.buyDate,
      holdingDays: h.holdingDays,
      createdAt: h.createdAt,
      buyFeeRate: h.buyFeeRate,
      buyFeeDeducted: h.buyFeeDeducted,
      buyFeeAmount: h.buyFeeAmount,
      sellFeeRate: h.sellFeeRate,
      serviceFeeRate: h.serviceFeeRate,
      serviceFeeDeducted: h.serviceFeeDeducted,
      lastFeeDate: h.lastFeeDate,
      nav: currentNav,
      navDate: navDate,
      navChange: dayChangePct,
      estimate: currentValue,
      estimateTime: estimateTime,
      estimateChange: estChange,
      marketValue: currentValue,
      todayChange: dayChangePct.toStringAsFixed(2),
      todayProfit: todayProfit,
      profit: profit,
      profitRate: profitRate.toStringAsFixed(2),
      valueSource: dataSource,
      sectors: null,
      changeLabel: changeLabel,
      changeUpdateTime: changeUpdateTime,
      navUpdated: navUpdated,
      hasError: hasError,
    );
  }

  /// 格式化日期为 yyyy-MM-dd
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  HoldingSummary _calcSummary(List<HoldingWithProfit> holdings) {
    if (holdings.isEmpty) {
      return HoldingSummary(
        totalValue: 0,
        totalCost: 0,
        totalProfit: 0,
        totalProfitRate: 0,
        todayProfit: 0,
      );
    }
    double totalCost = 0, totalValue = 0, todayProfit = 0;
    for (final h in holdings) {
      totalCost += h.amount;
      totalValue += h.marketValue;
      todayProfit += h.todayProfit;
    }
    final totalProfit = totalValue - totalCost;
    final totalProfitRate = totalCost > 0 ? totalProfit / totalCost : 0.0;
    return HoldingSummary(
      totalValue: totalValue,
      totalCost: totalCost,
      totalProfit: totalProfit,
      totalProfitRate: totalProfitRate,
      todayProfit: todayProfit,
    );
  }
}
