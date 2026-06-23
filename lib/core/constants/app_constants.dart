class AppConstants {
  static const String appName = '基金宝';
  static const String appVersion = '1.0.0';

  // 交易时间（分钟）
  static const int morningStart = 570; // 9:30
  static const int morningEnd = 690; // 11:30
  static const int afternoonStart = 780; // 13:00
  static const int afternoonEnd = 900; // 15:00

  // 缓存时间（毫秒）
  static const int estimateCacheTtl = 5000;
  static const int navCacheTtl = 5 * 60 * 1000; // 5分钟
  static const int marketCacheTtl = 60 * 1000; // 1分钟

  // 刷新间隔
  static const int autoRefreshInterval = 30 * 1000; // 30秒
}
