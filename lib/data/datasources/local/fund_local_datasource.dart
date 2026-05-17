import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_pkg;
import '../../../domain/entities/fund_entity.dart';

/// 本地存储数据源（shared_preferences + sqflite）
class FundLocalDataSource {
  static const String _holdingsKey = 'fund_holdings_v2';
  static const String _watchlistKey = 'fund_watchlist_v1';
  static const String _tradeRecordsKey = 'fund_trade_records';
  static const String _initializedKey = 'fund_app_initialized';

  SharedPreferences? _prefs;
  Database? _db;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      path_pkg.join(dbPath, 'fund_app.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE holdings (
            code TEXT PRIMARY KEY,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE trade_records (
            id TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            data TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  // ── 持仓 ──────────────────────────────────────────────

  Future<List<HoldingRecord>> getHoldings() async {
    try {
      final p = await prefs;
      final raw = p.getString(_holdingsKey);
      if (raw == null || raw.isEmpty) {
        return _getDemoHoldings();
      }
      final list = jsonDecode(raw) as List;
      return list.map((item) => HoldingRecord.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      print('[LocalDS] getHoldings error: $e');
      return _getDemoHoldings();
    }
  }

  List<HoldingRecord> _getDemoHoldings() {
    final now = DateTime.now();
    return [
      HoldingRecord(
        code: '012348',
        name: '天弘恒生科技指数(QDII)C',
        amount: 5000,
        shares: 5000 / 0.5432,
        buyNetValue: 0.5432,
        buyDate: now.subtract(const Duration(days: 30)).toIso8601String().split('T')[0],
        shareClass: 'C',
        createdAt: now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
        holdingDays: 30,
      ),
      HoldingRecord(
        code: '005827',
        name: '易方达蓝筹精选混合',
        amount: 10000,
        shares: 10000 / 2.1540,
        buyNetValue: 2.1540,
        buyDate: now.subtract(const Duration(days: 100)).toIso8601String().split('T')[0],
        shareClass: 'A',
        createdAt: now.subtract(const Duration(days: 100)).millisecondsSinceEpoch,
        holdingDays: 100,
      ),
    ];
  }

  Future<void> saveHoldings(List<HoldingRecord> holdings) async {
    try {
      final p = await prefs;
      await p.setString(_holdingsKey, jsonEncode(holdings.map((h) => h.toJson()).toList()));
    } catch (e) {
      print('[LocalDS] saveHoldings error: $e');
    }
  }

  Future<void> addOrUpdateHolding(HoldingRecord holding) async {
    final holdings = await getHoldings();
    final idx = holdings.indexWhere((h) => h.code == holding.code);
    if (idx >= 0) {
      holdings[idx] = holding;
    } else {
      holdings.add(holding);
    }
    await saveHoldings(holdings);
  }

  Future<void> removeHolding(String code) async {
    final holdings = await getHoldings();
    holdings.removeWhere((h) => h.code == code);
    await saveHoldings(holdings);
  }

  Future<bool> isHoldingInitialized() async {
    final p = await prefs;
    return p.getBool(_initializedKey) ?? false;
  }

  Future<void> setHoldingInitialized() async {
    final p = await prefs;
    await p.setBool(_initializedKey, true);
  }

  // ── 自选列表 ──────────────────────────────────────────────

  /// 演示基金名称（GBK 解码不靠谱，本地存 name）
  static const _demoFundNames = {
    '005827': '易方达蓝筹精选混合',
    '110022': '易方达消费行业股票',
    '012348': '天弘恒生科技ETF联接C',
    '001548': '天弘上证50ETF联接A',
    '320007': '诺安成长混合A',
    '016874': '广发远见智选混合C',
    '001631': '天弘中证食品饮料ETF联接A',
    '002407': '天弘中证证券保险C',
    '008592': '天弘中证电子ETF联接A',
  };

  Future<List<FundInfo>> getWatchlist() async {
    final p = await prefs;
    final raw = p.getString(_watchlistKey);
    final codeList = <String>[];
    if (raw == null || raw.isEmpty) {
      codeList.addAll(['005827', '110022', '012348', '001548', '320007', '016874']);
    } else {
      try {
        codeList.addAll(List<String>.from(jsonDecode(raw)));
      } catch (_) {
        codeList.addAll(['005827', '110022', '012348', '001548', '320007', '016874']);
      }
    }
    return codeList.map((code) => FundInfo(
      code: code,
      name: _demoFundNames[code] ?? code,
      type: '',
      pinyin: '',
    )).toList();
  }

  Future<void> addToWatchlist(String code, {String name = ''}) async {
    final p = await prefs;
    final raw = p.getString(_watchlistKey);
    List<String> list = [];
    if (raw != null && raw.isNotEmpty) {
      try { list.addAll(List<String>.from(jsonDecode(raw))); } catch (_) {}
    }
    if (!list.contains(code)) {
      list.add(code);
      await p.setString(_watchlistKey, jsonEncode(list));
    }
    // 同时存名称
    if (name.isNotEmpty) {
      final p2 = await prefs;
      await p2.setString('fund_name_$code', name);
    }
  }

  Future<void> removeFromWatchlist(String code) async {
    final p = await prefs;
    final raw = p.getString(_watchlistKey);
    List<String> list = [];
    if (raw != null && raw.isNotEmpty) {
      try { list.addAll(List<String>.from(jsonDecode(raw))); } catch (_) {}
    }
    list.remove(code);
    await p.setString(_watchlistKey, jsonEncode(list));
  }

  String? getFundName(String code) {
    return _demoFundNames[code];
  }

  // ── 交易记录 ──────────────────────────────────────────────

  Future<List<TradeRecord>> getTradeRecords({String? code}) async {
    final p = await prefs;
    final raw = p.getString(_tradeRecordsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final records = list.map((item) => TradeRecord(
        id: item['id'] ?? '',
        code: item['code'] ?? '',
        name: item['name'] ?? '',
        type: TradeType.values.firstWhere(
          (t) => t.name == item['type'],
          orElse: () => TradeType.buy,
        ),
        date: item['date'] ?? '',
        amount: (item['amount'] ?? 0).toDouble(),
        netValue: (item['netValue'] ?? 0).toDouble(),
        shares: (item['shares'] ?? 0).toDouble(),
        fee: (item['fee'] ?? 0).toDouble(),
        remark: item['remark'],
        createdAt: item['createdAt'] ?? 0,
        status: item['status'] != null
            ? TradeStatus.values.firstWhere((s) => s.name == item['status'], orElse: () => TradeStatus.completed)
            : null,
      )).toList();
      if (code != null) {
        return records.where((r) => r.code == code).toList();
      }
      return records;
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _tradeRecordToMap(TradeRecord r) {
    return {
      'id': r.id,
      'code': r.code,
      'name': r.name,
      'type': r.type.name,
      'date': r.date,
      'amount': r.amount,
      'netValue': r.netValue,
      'shares': r.shares,
      'fee': r.fee,
      'remark': r.remark,
      'createdAt': r.createdAt,
      'status': r.status?.name,
    };
  }

  Future<void> addTradeRecord(TradeRecord record) async {
    final records = await getTradeRecords();
    records.add(record);
    final p = await prefs;
    await p.setString(_tradeRecordsKey, jsonEncode(records.map(_tradeRecordToMap).toList()));
  }

  Future<void> removeTradeRecord(String id) async {
    final records = await getTradeRecords();
    records.removeWhere((r) => r.id == id);
    final p = await prefs;
    await p.setString(_tradeRecordsKey, jsonEncode(records.map(_tradeRecordToMap).toList()));
  }
}
