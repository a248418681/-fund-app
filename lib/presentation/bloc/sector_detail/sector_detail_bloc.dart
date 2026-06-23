import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import 'sector_detail_event.dart';
import 'sector_detail_state.dart';

class SectorDetailBloc extends Bloc<SectorDetailEvent, SectorDetailState> {
  final FundRepository _repository;

  SectorDetailBloc(this._repository) : super(const SectorDetailState()) {
    on<SectorDetailLoad>(_onLoad);
    on<SectorDetailSortFunds>(_onSortFunds);
  }

  Future<void> _onLoad(
      SectorDetailLoad event, Emitter<SectorDetailState> emit) async {
    emit(SectorDetailState(
      status: SectorDetailStatus.loading,
      sectorCode: event.code,
      sectorName: event.name,
      sectorPrice: event.price,
      sectorChangePercent: event.changePercent,
      sectorChange: event.change,
    ));
    try {
      // 并行加载成分股和关联基金
      final stocksFuture =
          _repository.fetchSectorConstituents(event.code).catchError((e) {
        debugPrint('[SectorDetailBloc] stocks load failed: $e');
        return <SectorConstituentItem>[];
      });

      // 基金：优先通过持仓明细管线获取，失败回退关键词搜索
      final fundsFuture = _repository
          .fetchSectorFundsByHoldings(event.code, event.name, pageSize: 30)
          .then((funds) {
        if (funds.isNotEmpty) return funds;
        debugPrint(
            '[SectorDetailBloc] holdings pipeline empty, fallback to keyword search');
        return _repository.fetchSectorFunds(event.name, pageSize: 20);
      }).catchError((e) {
        debugPrint(
            '[SectorDetailBloc] holdings pipeline failed: $e, fallback to keyword');
        return _repository
            .fetchSectorFunds(event.name, pageSize: 20)
            .catchError((e2) {
          debugPrint('[SectorDetailBloc] keyword search also failed: $e2');
          return <SectorFundItem>[];
        });
      });

      final results = await Future.wait([stocksFuture, fundsFuture]);
      final stocks = results[0] as List<SectorConstituentItem>;
      final funds = (results[1] as List<SectorFundItem>)
        ..sort((a, b) => b.estimateChange.compareTo(a.estimateChange));

      emit(state.copyWith(
        status: SectorDetailStatus.loaded,
        stocks: stocks,
        funds: funds,
      ));
    } catch (e) {
      debugPrint('[SectorDetailBloc] load error: $e');
      emit(state.copyWith(
        status: SectorDetailStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onSortFunds(
      SectorDetailSortFunds event, Emitter<SectorDetailState> emit) {
    final currentField = state.fundsSortField;
    final ascending = event.ascending ??
        (event.field == currentField ? !state.fundsSortAscending : false);

    final sorted = List<SectorFundItem>.from(state.funds);
    sorted.sort((a, b) {
      int cmp;
      switch (event.field) {
        case SectorFundSortField.price:
          cmp = b.netValue.compareTo(a.netValue);
          break;
        case SectorFundSortField.estimateChange:
          cmp = b.estimateChange.compareTo(a.estimateChange);
          break;
        case SectorFundSortField.name:
          cmp = a.name.compareTo(b.name);
          break;
        case SectorFundSortField.holdingMarketCap:
          cmp = b.holdingMarketCap.compareTo(a.holdingMarketCap);
          break;
      }
      return ascending ? -cmp : cmp;
    });

    emit(state.copyWith(
      funds: sorted,
      fundsSortField: event.field,
      fundsSortAscending: ascending,
    ));
  }
}
