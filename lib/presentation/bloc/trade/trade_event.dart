import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

abstract class TradeEvent extends Equatable {
  const TradeEvent();
  @override
  List<Object?> get props => [];
}

class TradeLoadRecords extends TradeEvent {
  final String? fundCode;
  const TradeLoadRecords({this.fundCode});
  @override
  List<Object?> get props => [fundCode];
}

class TradeAdd extends TradeEvent {
  final TradeRecord record;
  const TradeAdd(this.record);
  @override
  List<Object?> get props => [record];
}

class TradeDelete extends TradeEvent {
  final String id;
  const TradeDelete(this.id);
  @override
  List<Object?> get props => [id];
}

class TradeChangeFund extends TradeEvent {
  final FundAccurateData? fund;
  const TradeChangeFund(this.fund);
  @override
  List<Object?> get props => [fund];
}
