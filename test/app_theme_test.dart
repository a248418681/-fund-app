import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fund_app/core/theme/app_theme.dart';

void main() {
  group('AppTheme.changeColor（A股涨红跌绿）', () {
    test('正值为红（涨）', () {
      expect(AppTheme.changeColor(1.5), AppTheme.upColor);
    });
    test('负值为绿（跌）', () {
      expect(AppTheme.changeColor(-1.5), AppTheme.downColor);
    });
    test('零与 null 为平色', () {
      expect(AppTheme.changeColor(0), AppTheme.flatColor);
      expect(AppTheme.changeColor(null), AppTheme.flatColor);
    });
  });

  group('AppTheme.changeBgColor（pill 背景）', () {
    test('正/负/零分别返回对应浅背景', () {
      expect(AppTheme.changeBgColor(2), AppTheme.upBg);
      expect(AppTheme.changeBgColor(-2), AppTheme.downBg);
      expect(AppTheme.changeBgColor(0), AppTheme.flatBg);
      expect(AppTheme.changeBgColor(null), AppTheme.flatBg);
    });
  });

  group('AppTheme.formatPercent', () {
    test('正值带 + 号', () {
      expect(AppTheme.formatPercent(1.234), '+1.23%');
    });
    test('负值保留负号', () {
      expect(AppTheme.formatPercent(-1.5), '-1.50%');
    });
    test('null 返回占位符', () {
      expect(AppTheme.formatPercent(null), '--');
    });
    test('withSign=false 时正值不带 +', () {
      expect(AppTheme.formatPercent(1.0, withSign: false), '1.00%');
    });
  });

  group('AppTheme.formatMoney', () {
    test('默认前缀 ¥，两位小数', () {
      expect(AppTheme.formatMoney(1234.5), '¥1234.50');
    });
    test('null 返回占位符', () {
      expect(AppTheme.formatMoney(null), '--');
    });
  });

  group('AppTheme.formatNetValue', () {
    test('四位小数', () {
      expect(AppTheme.formatNetValue(1.5), '1.5000');
    });
    test('<=0 或 null 返回占位符', () {
      expect(AppTheme.formatNetValue(0), '--');
      expect(AppTheme.formatNetValue(null), '--');
    });
  });

  group('AppTheme.formatDate / formatTime', () {
    test('formatDate 取月-日', () {
      expect(AppTheme.formatDate('2026-06-23'), '06-23');
    });
    test('formatTime 取时间部分', () {
      expect(AppTheme.formatTime('2026-06-23 13:33'), '13:33');
    });
    test('空输入返回占位符', () {
      expect(AppTheme.formatDate(null), '--');
      expect(AppTheme.formatTime(''), '--');
    });
  });

  group('主题构建', () {
    test('亮/暗主题均启用 Material3', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });
  });
}
