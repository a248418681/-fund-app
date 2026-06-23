import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import 'trade_event.dart';
import 'trade_state.dart';

class TradeBloc extends Bloc<TradeEvent, TradeState> {
  final FundRepository _repository;

  TradeBloc(this._repository) : super(const TradeState()) {
    on<TradeLoadRecords>(_onLoadRecords);
    on<TradeAdd>(_onAdd);
    on<TradeDelete>(_onDelete);
    on<TradeChangeFund>(_onChangeFund);
  }

  Future<void> _onLoadRecords(
      TradeLoadRecords event, Emitter<TradeState> emit) async {
    emit(state.copyWith(status: TradeBlocStatus.loading));
    try {
      final records = await _repository.getTradeRecords(code: event.fundCode);
      emit(state.copyWith(status: TradeBlocStatus.loaded, records: records));
    } catch (e) {
      emit(state.copyWith(
          status: TradeBlocStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> _onAdd(TradeAdd event, Emitter<TradeState> emit) async {
    emit(state.copyWith(status: TradeBlocStatus.saving));
    try {
      await _repository.addTradeRecord(event.record);

      // 如果是买入，自动更新持仓
      if (event.record.type == TradeType.buy) {
        await _syncHoldingFromTrade(event.record);
      }

      final records = await _repository.getTradeRecords();
      emit(state.copyWith(status: TradeBlocStatus.saved, records: records));
    } catch (e) {
      emit(state.copyWith(
          status: TradeBlocStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> _onDelete(TradeDelete event, Emitter<TradeState> emit) async {
    try {
      await _repository.removeTradeRecord(event.id);
      final records = state.records.where((r) => r.id != event.id).toList();
      emit(state.copyWith(records: records));
    } catch (_) {}
  }

  void _onChangeFund(TradeChangeFund event, Emitter<TradeState> emit) {
    emit(state.copyWith(selectedFund: event.fund));
  }

  /// 根据交易记录同步持仓数据
  Future<void> _syncHoldingFromTrade(TradeRecord record) async {
    if (record.code.isEmpty || record.shares == 0) return;

    try {
      final existing = await _repository.getHoldings();
      final idx = existing.indexWhere((h) => h.code == record.code);

      if (idx >= 0) {
        final existingHolding = existing[idx];
        double totalShares;
        double totalAmount;

        if (record.shares > 0) {
          // 买入：累加份额和金额
          totalShares = existingHolding.shares + record.shares;
          totalAmount = existingHolding.amount + record.amount;
        } else {
          // 卖出：减份额和金额
          totalShares = existingHolding.shares + record.shares; // shares为负，自然减
          totalAmount = existingHolding.amount - record.amount; // amount为正，需减
        }

        if (totalShares <= 0) {
          // 全部卖出，删除持仓
          await _repository.removeHolding(record.code);
        } else {
          final avgNav = totalAmount / totalShares;
          final updated = existingHolding.copyWith(
            shares: totalShares,
            amount: totalAmount,
            buyNetValue: avgNav,
            buyDate: record.date.compareTo(existingHolding.buyDate) < 0
                ? record.date
                : existingHolding.buyDate,
          );
          await _repository.addOrUpdateHolding(updated);
        }
      } else if (record.shares > 0) {
        // 买入且无现有持仓 → 新增
        final newHolding = HoldingRecord(
          code: record.code,
          name: record.name,
          amount: record.amount,
          shares: record.shares,
          buyNetValue: record.netValue,
          buyDate: record.date,
          shareClass: 'A',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          holdingDays: 0,
        );
        await _repository.addOrUpdateHolding(newHolding);
      }
      // 卖出且无现有持仓 → 忽略（不应发生）
    } catch (e) {
      debugPrint('TradeBloc: _syncHoldingFromTrade error: $e');
    }
  }
}
