import '../entities/fund_entity.dart';

abstract class FundRepository {
  /// 获取单只基金实时估值
  Future<FundEstimate> fetchFundEstimate(String code);

  /// 批量获取基金实时估值
  Future<Map<String, FundEstimate>> fetchFundEstimates(List<String> codes);

  /// 获取基金列表（搜索用）
  Future<List<FundInfo>> fetchFundList();

  /// 搜索基金
  Future<List<FundInfo>> searchFund(String keyword, {int limit = 50});

  /// 获取历史净值
  Future<List<NetValueRecord>> fetchNetValueHistory(String code, {int days = 30});

  /// 获取大盘指数
  Future<List<MarketIndex>> fetchMarketIndices();

  /// 获取基金排行榜
  Future<List<FundRankItem>> fetchFundRanking({
    String sortType = 'r',
    String order = 'desc',
    int pageSize = 20,
    String fundType = 'all',
  });

  /// 获取基金准确数据（估值+净值综合）
  Future<FundAccurateData> fetchFundAccurateData(String code);

  /// 获取阶段涨幅
  Future<List<PeriodReturn>> fetchPeriodReturns(String code);

  /// 获取基金详细信息
  Future<FundAccurateData?> fetchFundDetailInfo(String code);

  /// 获取基金经理列表
  Future<List<FundManagerInfo>> fetchFundManagerInfo(String code);

  /// 获取行业配置
  Future<List<IndustryAllocation>> fetchIndustryAllocation(String code);

  /// 获取资产配置
  Future<AssetAllocation?> fetchAssetAllocation(String code);

  /// 获取重仓股
  Future<List<StockHolding>> fetchStockHoldings(String code);

  /// 获取重仓股（含名称和涨跌幅）
  Future<List<StockHolding>> fetchStockHoldingsWithInfo(String code);

  /// 获取财经新闻
  Future<List<NewsItem>> fetchFinanceNews({int pageSize = 10, String category = '102'});

  /// 获取热门板块排行
  Future<List<SectorRankItem>> fetchSectorRanking({int pageSize = 10});

  /// 获取板块成分股/基列表
  Future<List<SectorConstituentItem>> fetchSectorConstituents(String sectorCode, {int pageSize = 50});

  /// 获取关联板块信息（根据基金名称识别板块 + 市场行情）
  Future<SectorInfo?> fetchSectorInfo(String fundName, String fundType, String fundCode);

  /// 获取板块关联基金
  Future<List<SectorFundItem>> fetchSectorFunds(String sectorName, {int pageSize = 20});

  /// 持仓相关
  Future<List<HoldingRecord>> getHoldings();
  Future<void> saveHoldings(List<HoldingRecord> holdings);
  Future<void> addOrUpdateHolding(HoldingRecord holding);
  Future<void> removeHolding(String code);

  /// 自选列表
  Future<List<FundInfo>> getWatchlist();
  Future<void> addToWatchlist(String code, {String name = ''});
  Future<void> removeFromWatchlist(String code);

  /// 交易记录
  Future<List<TradeRecord>> getTradeRecords({String? code});
  Future<void> addTradeRecord(TradeRecord record);
  Future<void> removeTradeRecord(String id);
}
