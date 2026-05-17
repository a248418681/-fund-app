import 'package:equatable/equatable.dart';

abstract class SectorDetailEvent extends Equatable {
  const SectorDetailEvent();

  @override
  List<Object?> get props => [];
}

/// 加载板块详情
class SectorDetailLoad extends SectorDetailEvent {
  final String code;
  final String name;
  final double price;
  final double changePercent;
  final double change;

  const SectorDetailLoad({
    required this.code,
    required this.name,
    required this.price,
    required this.changePercent,
    required this.change,
  });

  @override
  List<Object?> get props => [code, name, price, changePercent, change];
}
