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
  }

  Future<void> _onLoad(SectorDetailLoad event, Emitter<SectorDetailState> emit) async {
    emit(SectorDetailState(
      status: SectorDetailStatus.loading,
      sectorCode: event.code,
      sectorName: event.name,
      sectorPrice: event.price,
      sectorChangePercent: event.changePercent,
      sectorChange: event.change,
    ));
    try {
      // 并行加载成分股和关联基金，任一失败不影响另一个
      final stocksResult = await _repository.fetchSectorConstituents(event.code).catchError((e) {
        debugPrint('[SectorDetailBloc] stocks load failed: $e');
        return <SectorConstituentItem>[];
      });
      final fundsResult = await _repository.fetchSectorFunds(event.name, pageSize: 20).catchError((e) {
        debugPrint('[SectorDetailBloc] funds load failed: $e');
        return <SectorFundItem>[];
      });
      emit(state.copyWith(
        status: SectorDetailStatus.loaded,
        stocks: stocksResult,
        funds: fundsResult,
      ));
    } catch (e) {
      debugPrint('[SectorDetailBloc] load error: $e');
      emit(state.copyWith(
        status: SectorDetailStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }
}
