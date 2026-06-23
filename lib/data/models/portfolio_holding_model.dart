/// 基金持仓（重仓股票）数据模型
class PortfolioHolding {
  final String stockCode;
  final String stockName;
  final double ratio; // 持仓比例(%)

  const PortfolioHolding({
    required this.stockCode,
    required this.stockName,
    this.ratio = 0.0,
  });

  factory PortfolioHolding.fromJson(Map<String, dynamic> json) =>
      PortfolioHolding(
        stockCode:
            (json['stockCode'] ?? json['SENCCODE'] ?? json['SZCODE'] ?? '')
                .toString(),
        stockName: (json['stockName'] ?? json['SNAME'] ?? json['SZNAME'] ?? '')
            .toString(),
        ratio: _parseD(json['ratio'] ?? json['JZBL'] ?? json['SZJZBL']),
      );

  static double _parseD(dynamic v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
}
