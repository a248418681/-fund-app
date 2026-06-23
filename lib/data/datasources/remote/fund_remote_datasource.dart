import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../domain/entities/fund_entity.dart';
import 'internal_models.dart';
import 'remote_dio_accessor.dart';
import 'mixin_estimate.dart';
import 'mixin_pzdata.dart';
import 'mixin_danjuan.dart';
import 'mixin_market.dart';
import 'mixin_sector.dart';

/// 基类：实现 [RemoteDioAccessor] 以满足所有 mixin 的 `on` 约束
abstract class _RemoteDataSourceBase implements RemoteDioAccessor {}

/// 天天基金远程数据源（Facade）
///
/// 通过 mixin 组合 5 个职责模块：
/// - [FundEstimateDataSource] — 估值/净值 API + 三级降级
/// - [PzDataDataSource] — pingzhongdata 解析
/// - [DanjuanDataSource] — 蛋卷 API + 重仓股/行业/资产配置
/// - [MarketDataSource] — 市场指数/排行/搜索/新闻
/// - [SectorDataSource] — 板块行情/成分股/关联基金
///
/// 外部调用方零改动：所有公开方法签名保持不变。
class FundRemoteDataSource extends _RemoteDataSourceBase
    with
        FundEstimateDataSource,
        PzDataDataSource,
        DanjuanDataSource,
        MarketDataSource,
        SectorDataSource {
  final Dio _dio;

  FundRemoteDataSource(this._dio);

  @override
  Dio get dio => _dio;

  // ── 三级降级：GZ+PZ → 仅PZ → 蛋卷 → 抛异常 ──
  Future<FundAccurateData> fetchFundAccurateData(String code) async {
    // Level 1: GZ + PZ 并行
    Map<String, dynamic>? gz;
    PzData? pz;

    try {
      gz = await fetchFundGZ(code);
    } catch (e) {
      debugPrint('[API] GZ失败($code): $e, 降级为仅PZ');
    }

    try {
      pz = await fetchPzData(code);
    } catch (e) {
      debugPrint('[API] PZ失败($code): $e');
    }

    // GZ 成功 → 最优路径
    if (gz != null) {
      return FundAccurateData(
        code: code,
        name: pz?.fSName ?? gz['name'] ?? '',
        nav: double.tryParse(gz['dwjz']?.toString() ?? '0') ?? 0.0,
        navDate: (gz['jzrq'] ?? '').replaceAll('-', ''),
        navChange: 0.0,
        estimate: double.tryParse(gz['gsz']?.toString() ?? '0') ?? 0.0,
        estimateTime: gz['gztime'] ?? '',
        estimateChange: double.tryParse(gz['gszzl']?.toString() ?? '0') ?? 0.0,
        prevClose: 0.0,
        currentValue: double.tryParse(gz['gsz']?.toString() ?? '0') ?? 0.0,
        dayChange: pz?.netWorthTrend.isNotEmpty == true
            ? ((pz!.netWorthTrend.last
                        as Map<String, dynamic>)['equityReturn'] ??
                    0)
                .toDouble()
            : 0.0,
        dataSource: 'gz+pz',
        fundType: '',
        company: '',
        manager:
            pz?.managers.isNotEmpty == true ? pz!.managers[0]['name'] : null,
      );
    }

    // Level 2: 仅 PZ
    if (pz != null) {
      final navList = pz.netWorthTrend;
      double lastNav = 0, prevNav = 0;
      String lastNavDate = '';
      if (navList.length >= 2) {
        final last = navList[navList.length - 1] as Map<String, dynamic>;
        final prev = navList[navList.length - 2] as Map<String, dynamic>;
        lastNav = (last['y'] ?? 0).toDouble();
        prevNav = (prev['y'] ?? 0).toDouble();
        final xVal = last['x'];
        if (xVal is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(xVal);
          lastNavDate =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      } else if (navList.length == 1) {
        final last = navList[0] as Map<String, dynamic>;
        lastNav = (last['y'] ?? 0).toDouble();
        final xVal = last['x'];
        if (xVal is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(xVal);
          lastNavDate =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      }

      final dayChg = (prevNav > 0 && lastNav > 0)
          ? (lastNav - prevNav) / prevNav * 100
          : 0.0;

      if (lastNav > 0) {
        debugPrint(
            '[API] 仅PZ降级($code): nav=$lastNav, dayChange=${dayChg.toStringAsFixed(2)}%');
        return FundAccurateData(
          code: code,
          name: pz.fSName ?? '',
          nav: lastNav,
          navDate: lastNavDate.replaceAll('-', ''),
          navChange: 0.0,
          estimate: lastNav,
          estimateTime: '',
          estimateChange: dayChg,
          prevClose: prevNav,
          currentValue: lastNav,
          dayChange: dayChg,
          dataSource: 'pz-only',
          fundType: '',
          company: '',
          manager: pz.managers.isNotEmpty ? pz.managers[0]['name'] : null,
        );
      }

      // 货币基金兜底
      if (pz.millionCopiesIncome.isNotEmpty) {
        final incomeList = pz.millionCopiesIncome;
        final lastIncome = incomeList[incomeList.length - 1];
        final lastY =
            (lastIncome is Map ? lastIncome['y'] : (lastIncome as List)[1])
                    ?.toDouble() ??
                0.0;
        final lastX =
            lastIncome is Map ? lastIncome['x'] : (lastIncome as List)[0];
        String incomeDate = lastNavDate;
        if (lastX is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(lastX);
          incomeDate =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
        debugPrint(
            '[API] 货币基金PZ降级($code): millionCopiesIncome=${incomeList.length}, lastY=$lastY');
        return FundAccurateData(
          code: code,
          name: pz.fSName ?? '',
          nav: 0.0,
          navDate: incomeDate.replaceAll('-', ''),
          navChange: 0.0,
          estimate: 0.0,
          estimateTime: '',
          estimateChange: 0.0,
          prevClose: 0.0,
          currentValue: 0.0,
          dayChange: 0.0,
          dataSource: 'pz-million',
          fundType: '',
          company: '',
          manager: pz.managers.isNotEmpty ? pz.managers[0]['name'] : null,
        );
      }

      debugPrint('[API] PZ降级($code): NAV=0且无millionCopiesIncome, 继续降级至蛋卷API');
    }

    // Level 3: 蛋卷
    try {
      final dj = await fetchDjData(code);
      if (dj != null) {
        debugPrint('[API] 蛋卷降级($code): stocks=${dj.stockList.length}');
        return FundAccurateData(
          code: code,
          name: '',
          nav: 0,
          navDate: '',
          navChange: 0.0,
          estimate: 0,
          estimateTime: '',
          estimateChange: 0.0,
          prevClose: 0.0,
          currentValue: 0,
          dayChange: 0.0,
          dataSource: 'danjuan',
          fundType: '',
          company: '',
        );
      }
    } catch (e) {
      debugPrint('[API] 蛋卷降级也失败($code): $e');
    }

    throw Exception('获取基金数据失败：所有数据源均不可用($code)');
  }

  /// 获取基金详情信息（兼容旧接口）
  Future<FundAccurateData?> fetchFundDetailInfo(String code) async {
    try {
      return await fetchFundAccurateData(code);
    } catch (e) {
      debugPrint('[API] fetchFundDetailInfo error ($code): $e');
      return null;
    }
  }

  /// 获取行业配置（蛋卷优先 → pingzhongdata 降级）
  @override
  Future<List<IndustryAllocation>> fetchIndustryAllocation(String code) async {
    final djResult = await super.fetchIndustryAllocation(code);
    if (djResult.isNotEmpty) return djResult;

    // 降级：pingzhongdata
    try {
      final pz = await fetchPzData(code);
      return pz.industryItems.map((item) {
        final map = item as Map<String, dynamic>;
        return IndustryAllocation(
          name: (map['name'] ?? '').toString(),
          industry: (map['name'] ?? '').toString(),
          percent: (map['y'] ?? 0).toDouble(),
          proportion: (map['y'] ?? 0).toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[IndustryAllocation] fallback error: $e');
      return [];
    }
  }

  /// 获取资产配置（蛋卷优先 → pingzhongdata 降级）
  @override
  Future<AssetAllocation?> fetchAssetAllocation(String code) async {
    final djResult = await super.fetchAssetAllocation(code);
    if (djResult != null) return djResult;

    try {
      final pz = await fetchPzData(code);
      if (pz.assetSeries.isEmpty) return null;

      double stocks = 0, bonds = 0, cash = 0, others = 0;
      for (final item in pz.assetSeries) {
        final map = item as Map<String, dynamic>;
        final name = (map['name'] ?? '').toString();
        if (map['data'] is List && (map['data'] as List).isNotEmpty) {
          final data = map['data'] as List;
          final latestValue = (data.last as num?)?.toDouble() ?? 0.0;
          if (name.contains('股票')) {
            stocks = latestValue;
          } else if (name.contains('债券')) {
            bonds = latestValue;
          } else if (name.contains('现金')) {
            cash = latestValue;
          } else if (name.contains('其他')) {
            others = latestValue;
          }
        }
      }
      return AssetAllocation(
          stocks: stocks, bonds: bonds, cash: cash, others: others);
    } catch (e) {
      debugPrint('[API] fetchAssetAllocation error ($code): $e');
      return null;
    }
  }

  /// 清除所有缓存
  void clearCache() {
    clearGzCache();
    clearPzCache();
    clearDjCache();
    debugPrint('[API] 所有缓存已清除');
  }
}
