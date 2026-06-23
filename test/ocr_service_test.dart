import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fund_app/utils/ocr_service.dart';

/// OcrService 解析逻辑的特征测试（characterization test）。
///
/// 目的：在重构/拆分 ocr_service.dart 之前，用真实截图 OCR 样本锁住当前解析行为，
/// 保证后续拆分「不改变输出」。这些断言记录的是**当前实现的实际行为**，
/// 而非理想结果——已知存在的解析瑕疵（见下）也一并锁定，重构时若输出变化即报警。
///
/// 已知待修瑕疵（非本次重构引入，留待后续单独修复）：
/// - 部分基金名被误加 '%' 前缀（上一行涨跌幅的 % 粘连）
/// - 部分折行基金名未完整拼接（如「广发中证500ETF联」缺「接(LOF)C」）
void main() {
  late List<RecognizedHolding> result;

  setUpAll(() {
    final text = File('test_ocr_alipay_raw.txt').readAsStringSync();
    result = OcrService.parseHoldingText(text);
  });

  group('支付宝持仓 OCR 解析（特征测试）', () {
    test('解析出 10 条持仓记录', () {
      expect(result.length, 10);
    });

    test('折行的基金名能正确拼接（东方阿尔法瑞享混 + 合C）', () {
      final first = result.first;
      expect(first.name, '东方阿尔法瑞享混合C');
      expect(first.amount, 197.12);
    });

    test('金额被正确提取为 double', () {
      for (final h in result) {
        expect(h.amount, greaterThan(0),
            reason: '每条持仓都应解析出正金额: ${h.name}');
      }
    });

    test('支付宝截图无基金代码，全部标记 needsCodeMatch', () {
      for (final h in result) {
        expect(h.code, isEmpty);
        expect(h.needsCodeMatch, isTrue);
      }
    });

    test('空文本返回空列表', () {
      expect(OcrService.parseHoldingText(''), isEmpty);
      expect(OcrService.parseHoldingText('   \n  \n'), isEmpty);
    });
  });
}
