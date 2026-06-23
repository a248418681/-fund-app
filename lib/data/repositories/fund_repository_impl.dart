import 'package:dio/dio.dart';
import '../datasources/remote/fund_remote_datasource.dart';
import '../datasources/local/fund_local_datasource.dart';
import '../../domain/entities/fund_entity.dart';
import '../../domain/repositories/fund_repository.dart';

class FundRepositoryImpl implements FundRepository {
  final FundRemoteDataSource _remote;
  final FundLocalDataSource _local;

  FundRepositoryImpl(this._remote, this._local);

  @override
  Future<FundEstimate> fetchFundEstimate(String code) async {
    return await _remote.fetchFundEstimate(code);
  }

  @override
  Future<Map<String, FundEstimate>> fetchFundEstimates(
      List<String> codes) async {
    return await _remote.fetchFundEstimates(codes);
  }

  @override
  Future<List<FundInfo>> fetchFundList() async {
    return await _remote.fetchFundList();
  }

  @override
  Future<List<FundInfo>> searchFund(String keyword,
      {int limit = 50, CancelToken? cancelToken}) async {
    return await _remote.searchFund(keyword,
        limit: limit, cancelToken: cancelToken);
  }

  @override
  Future<List<NetValueRecord>> fetchNetValueHistory(String code,
      {int days = 30}) async {
    return await _remote.fetchNetValueHistory(code, days: days);
  }

  @override
  Future<List<MarketIndex>> fetchMarketIndices() async {
    return await _remote.fetchMarketIndices();
  }

  @override
  Future<List<FundRankItem>> fetchFundRanking({
    String sortType = 'r',
    String order = 'desc',
    int pageSize = 20,
    String fundType = 'all',
  }) async {
    return await _remote.fetchFundRanking(
      sortType: sortType,
      order: order,
      pageSize: pageSize,
      fundType: fundType,
    );
  }

  @override
  Future<FundAccurateData> fetchFundAccurateData(String code) async {
    return await _remote.fetchFundAccurateData(code);
  }

  @override
  Future<List<PeriodReturn>> fetchPeriodReturns(String code) async {
    return await _remote.fetchPeriodReturns(code);
  }

  @override
  Future<FundAccurateData?> fetchFundDetailInfo(String code) async {
    return await _remote.fetchFundDetailInfo(code);
  }

  @override
  Future<List<FundManagerInfo>> fetchFundManagerInfo(String code) async {
    return await _remote.fetchFundManagerInfo(code);
  }

  @override
  Future<List<IndustryAllocation>> fetchIndustryAllocation(String code) async {
    return await _remote.fetchIndustryAllocation(code);
  }

  @override
  Future<AssetAllocation?> fetchAssetAllocation(String code) async {
    return await _remote.fetchAssetAllocation(code);
  }

  @override
  Future<List<StockHolding>> fetchStockHoldings(String code) async {
    return await _remote.fetchStockHoldings(code);
  }

  @override
  Future<List<StockHolding>> fetchStockHoldingsWithInfo(String code) async {
    return await _remote.fetchStockHoldingsWithInfo(code);
  }

  @override
  Future<List<NewsItem>> fetchFinanceNews(
      {int pageSize = 10, String category = '102'}) async {
    return await _remote.fetchFinanceNews(
        pageSize: pageSize, category: category);
  }

  @override
  Future<List<SectorRankItem>> fetchSectorRanking({int pageSize = 10}) async {
    return await _remote.fetchSectorRanking(pageSize: pageSize);
  }

  @override
  Future<List<SectorConstituentItem>> fetchSectorConstituents(String sectorCode,
      {int pageSize = 50}) async {
    return await _remote.fetchSectorConstituents(sectorCode,
        pageSize: pageSize);
  }

  @override
  Future<SectorInfo?> fetchSectorInfo(
      String fundName, String fundType, String fundCode) async {
    return await _remote.fetchSectorInfo(fundName, fundType, fundCode);
  }

  // ══════════════════════════════════════════════════════════════════════
  // 本地数据操作
  // ══════════════════════════════════════════════════════════════════════

  @override
  Future<List<SectorFundItem>> fetchSectorFunds(String sectorName,
      {int pageSize = 20}) async {
    return await _remote.fetchSectorFunds(sectorName, pageSize: pageSize);
  }

  @override
  Future<List<SectorFundItem>> fetchSectorFundsByHoldings(
      String sectorCode, String sectorName,
      {int pageSize = 30}) async {
    return await _remote.fetchSectorFundsByHoldings(sectorCode, sectorName,
        pageSize: pageSize);
  }

  @override
  Future<List<HoldingRecord>> getHoldings() => _local.getHoldings();

  @override
  Future<void> saveHoldings(List<HoldingRecord> holdings) =>
      _local.saveHoldings(holdings);

  @override
  Future<void> addOrUpdateHolding(HoldingRecord holding) =>
      _local.addOrUpdateHolding(holding);

  @override
  Future<void> removeHolding(String code) => _local.removeHolding(code);

  @override
  Future<List<FundInfo>> getWatchlist() => _local.getWatchlist();

  @override
  Future<void> addToWatchlist(String code, {String name = ''}) =>
      _local.addToWatchlist(code, name: name);

  @override
  Future<void> removeFromWatchlist(String code) =>
      _local.removeFromWatchlist(code);

  @override
  Future<List<TradeRecord>> getTradeRecords({String? code}) =>
      _local.getTradeRecords(code: code);

  @override
  Future<void> addTradeRecord(TradeRecord record) =>
      _local.addTradeRecord(record);

  @override
  Future<void> removeTradeRecord(String id) => _local.removeTradeRecord(id);
}
