import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum TradeBlocStatus { initial, loading, loaded, saving, saved, error }

class TradeState extends Equatable {
  final TradeBlocStatus status;
  final List<TradeRecord> records;
  final FundAccurateData? selectedFund;
  final String? errorMessage;

  const TradeState({
    this.status = TradeBlocStatus.initial,
    this.records = const [],
    this.selectedFund,
    this.errorMessage,
  });

  TradeState copyWith({
    TradeBlocStatus? status,
    List<TradeRecord>? records,
    FundAccurateData? selectedFund,
    String? errorMessage,
  }) {
    return TradeState(
      status: status ?? this.status,
      records: records ?? this.records,
      selectedFund: selectedFund ?? this.selectedFund,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, records, selectedFund, errorMessage];
}
