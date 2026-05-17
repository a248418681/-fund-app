import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '../../data/datasources/remote/fund_remote_datasource.dart';
import '../../data/datasources/local/fund_local_datasource.dart';
import '../../data/repositories/fund_repository_impl.dart';
import '../../domain/repositories/fund_repository.dart';
import '../../presentation/bloc/home/home_bloc.dart';
import '../../presentation/bloc/holdings/holdings_bloc.dart';
import '../../presentation/bloc/detail/detail_bloc.dart';
import '../../presentation/bloc/market/market_bloc.dart';
import '../../presentation/bloc/search/search_bloc.dart';
import '../../presentation/bloc/sector_detail/sector_detail_bloc.dart';
import '../../presentation/bloc/trade/trade_bloc.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  // Register Dio first
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));
  
  // 修复 MIME type 解析问题：使用 BackgroundTransformer 不做 content-type 检查
  dio.transformer = BackgroundTransformer();
  
  getIt.registerSingleton<Dio>(dio);

  // Data Sources - LazySingleton 以保留内存缓存(gzCache/pzCache/djCache)
  getIt.registerLazySingleton<FundRemoteDataSource>(() => FundRemoteDataSource(
        getIt.get<Dio>(),
      ));
  getIt.registerLazySingleton<FundLocalDataSource>(() => FundLocalDataSource());

  // Repository - LazySingleton 共享数据源实例
  getIt.registerLazySingleton<FundRepository>(
    () => FundRepositoryImpl(getIt<FundRemoteDataSource>(), getIt<FundLocalDataSource>()),
  );

  // BLoCs - DetailBloc 每次(Factory)，其他共享状态用 lazySingleton
  getIt.registerLazySingleton<HomeBloc>(() => HomeBloc(getIt<FundRepository>()));
  getIt.registerLazySingleton<HoldingsBloc>(() => HoldingsBloc(getIt<FundRepository>()));
  getIt.registerFactory<DetailBloc>(() => DetailBloc(getIt<FundRepository>()));
  getIt.registerFactory<SectorDetailBloc>(() => SectorDetailBloc(getIt<FundRepository>()));
  getIt.registerLazySingleton<MarketBloc>(() => MarketBloc(getIt<FundRepository>()));
  getIt.registerLazySingleton<SearchBloc>(() => SearchBloc(getIt<FundRepository>()));
  getIt.registerFactory<TradeBloc>(() => TradeBloc(getIt<FundRepository>()));
}

