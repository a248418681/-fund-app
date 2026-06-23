/// 交易时间工具类（统一入口）
/// 节假日表需每年更新
class TradingCalendar {
  /// 2026年法定节假日（不含周末调休）
  // TODO: 每年初更新当年节假日
  static const Set<String> _holidays2026 = {
    // ── 上半年 ──
    '20260101', '20260102', // 元旦
    '20260217', '20260218', '20260219', '20260220', '20260221', '20260222',
    '20260223', // 春节
    '20260405', '20260406', // 清明
    '20260501', '20260502', '20260503', // 劳动节
    '20260531', '20260601', // 端午
    // ── 下半年 ──
    '20260925', '20260926', '20260927', // 中秋
    '20261001', '20261002', '20261003', '20261004', '20261005', '20261006',
    '20261007', // 国庆
  };

  /// 判断是否为交易日（周一到周五 + 排除节假日）
  static bool isTradingDay(DateTime date) {
    if (date.weekday == 6 || date.weekday == 7) return false;
    final ds = '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    return !_holidays2026.contains(ds);
  }

  /// 是否在交易时段内（排除午休）
  /// 上午盘：9:30-11:30，下午盘：13:00-15:00
  /// 用于决定是否刷新估值（午休期间估值不变，无需刷新）
  static bool isTradingSession([DateTime? now]) {
    now ??= DateTime.now();
    if (!isTradingDay(now)) return false;
    final timeMinutes = now.hour * 60 + now.minute;
    // 上午盘：9:30-11:30 (570-690)
    if (timeMinutes >= 570 && timeMinutes < 690) return true;
    // 下午盘：13:00-15:00 (780-900)
    if (timeMinutes >= 780 && timeMinutes < 900) return true;
    return false;
  }

  /// 是否在市场开放时间内（9:30-15:00 连续，含午休）
  /// 用于持仓页标签判断：午休期间估值仍有参考价值，
  /// 应显示"当日估算涨跌"而非"上一交易日涨跌"
  static bool isMarketOpen([DateTime? now]) {
    now ??= DateTime.now();
    if (!isTradingDay(now)) return false;
    final timeMinutes = now.hour * 60 + now.minute;
    return timeMinutes >= 570 && timeMinutes < 900;
  }

  /// 判断当前是否在交易日内（不含时间段限制）
  static bool isTodayTradingDay() => isTradingDay(DateTime.now());
}
