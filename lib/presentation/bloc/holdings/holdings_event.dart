import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';
import 'holdings_state.dart';

abstract class HoldingsEvent extends Equatable {
  const HoldingsEvent();
  @override
  List<Object?> get props => [];
}

class HoldingsLoad extends HoldingsEvent {}

/// HoldingsInit = HoldingsLoad（别名，兼容旧调用）
class HoldingsInit extends HoldingsLoad {}

class HoldingsRefresh extends HoldingsEvent {}

/// 静默刷新：后台拉数据，不设 isRefreshing 标志，数据不变不触发 rebuild
class HoldingsSilentRefresh extends HoldingsEvent {}

class HoldingsAdd extends HoldingsEvent {
  final HoldingRecord holding;
  const HoldingsAdd(this.holding);
  @override
  List<Object?> get props => [holding];
}

class HoldingsUpdate extends HoldingsEvent {
  final HoldingRecord holding;
  const HoldingsUpdate(this.holding);
  @override
  List<Object?> get props => [holding];
}

class HoldingsDelete extends HoldingsEvent {
  final String code;
  const HoldingsDelete(this.code);
  @override
  List<Object?> get props => [code];
}

/// 内部事件：自动刷新定时器 tick
class HoldingsAutoRefreshTick extends HoldingsEvent {}

/// 切换排序
class HoldingsChangeSort extends HoldingsEvent {
  final HoldingsSortField field;
  const HoldingsChangeSort(this.field);
  @override
  List<Object?> get props => [field];
}
