import 'package:equatable/equatable.dart';
import '../../../domain/entities/fund_entity.dart';

enum SectorDetailStatus { initial, loading, loaded, error }

class SectorDetailState extends Equatable {
  final SectorDetailStatus status;
  final String sectorCode;
  final String sectorName;
  final double sectorPrice;
  final double sectorChangePercent;
  final double sectorChange;
  final List<SectorConstituentItem> stocks;
  final List<SectorFundItem> funds;
  final String? errorMessage;

  const SectorDetailState({
    this.status = SectorDetailStatus.initial,
    this.sectorCode = '',
    this.sectorName = '',
    this.sectorPrice = 0,
    this.sectorChangePercent = 0,
    this.sectorChange = 0,
    this.stocks = const [],
    this.funds = const [],
    this.errorMessage,
  });

  SectorDetailState copyWith({
    SectorDetailStatus? status,
    String? sectorCode,
    String? sectorName,
    double? sectorPrice,
    double? sectorChangePercent,
    double? sectorChange,
    List<SectorConstituentItem>? stocks,
    List<SectorFundItem>? funds,
    String? errorMessage,
  }) {
    return SectorDetailState(
      status: status ?? this.status,
      sectorCode: sectorCode ?? this.sectorCode,
      sectorName: sectorName ?? this.sectorName,
      sectorPrice: sectorPrice ?? this.sectorPrice,
      sectorChangePercent: sectorChangePercent ?? this.sectorChangePercent,
      sectorChange: sectorChange ?? this.sectorChange,
      stocks: stocks ?? this.stocks,
      funds: funds ?? this.funds,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, sectorCode, sectorName, sectorPrice, sectorChangePercent, sectorChange, stocks, funds, errorMessage];
}
