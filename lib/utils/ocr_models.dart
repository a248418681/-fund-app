// OCR 解析相关的数据模型
//
// 从 ocr_service.dart 抽出，便于复用与减小主文件体积。
// 这些是被外部（screenshot_import_page）直接引用的公共模型。

/// 识别出的单条持仓
class RecognizedHolding {
  final String code;
  final String name;
  final double amount;
  final double? shares;
  final double? yesterdayProfit;
  final double? holdingProfit;
  final double? holdingProfitRate;
  final double confidence;
  final bool needsCodeMatch;

  RecognizedHolding({
    required this.code,
    required this.name,
    required this.amount,
    this.shares,
    this.yesterdayProfit,
    this.holdingProfit,
    this.holdingProfitRate,
    this.confidence = 0.5,
    this.needsCodeMatch = false,
  });

  RecognizedHolding copyWith({
    String? code,
    String? name,
    double? amount,
    double? shares,
    double? yesterdayProfit,
    double? holdingProfit,
    double? holdingProfitRate,
    double? confidence,
    bool? needsCodeMatch,
  }) {
    return RecognizedHolding(
      code: code ?? this.code,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      shares: shares ?? this.shares,
      yesterdayProfit: yesterdayProfit ?? this.yesterdayProfit,
      holdingProfit: holdingProfit ?? this.holdingProfit,
      holdingProfitRate: holdingProfitRate ?? this.holdingProfitRate,
      confidence: confidence ?? this.confidence,
      needsCodeMatch: needsCodeMatch ?? this.needsCodeMatch,
    );
  }
}

/// 截图格式
enum ScreenshotFormat { alipay, tiantian, generic }

/// V9 用的 Block 数据结构（带坐标的 OCR 文本块）
class OcrBlock {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  OcrBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  double get centerx => left + (right - left) / 2;
  double get centery => top + (bottom - top) / 2;
}
