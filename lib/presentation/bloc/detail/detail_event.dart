import 'package:equatable/equatable.dart';
import 'detail_state.dart';

abstract class DetailEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class DetailLoad extends DetailEvent {
  final String code;
  DetailLoad(this.code);
  @override
  List<Object?> get props => [code];
}

class DetailRefresh extends DetailEvent {
  final String code;
  DetailRefresh(this.code);
  @override
  List<Object?> get props => [code];
}

class DetailLoadNavHistory extends DetailEvent {
  final String code;
  final int days;
  DetailLoadNavHistory(this.code, {this.days = 90});
  @override
  List<Object?> get props => [code, days];
}

class DetailLoadPeriodReturns extends DetailEvent {
  final String code;
  DetailLoadPeriodReturns(this.code);
  @override
  List<Object?> get props => [code];
}

class DetailChangeNavPeriod extends DetailEvent {
  final String code;
  final NavPeriod period;
  DetailChangeNavPeriod(this.code, this.period);
  @override
  List<Object?> get props => [code, period];
}
