import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/di/injection.dart';
import 'presentation/bloc/home/home_bloc.dart';
import 'presentation/bloc/holdings/holdings_bloc.dart';
import 'presentation/bloc/market/market_bloc.dart';
import 'presentation/bloc/observer/app_bloc_observer.dart';
import 'presentation/pages/settings/settings_page.dart';
import 'utils/ocr_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  // 后台加载公司名列表（不阻塞启动）
  OcrService.initCompanyNames();
  Bloc.observer = AppBlocObserver();
  runApp(const FundApp());
}

class FundApp extends StatefulWidget {
  const FundApp({super.key});

  @override
  State<FundApp> createState() => _FundAppState();
}

class _FundAppState extends State<FundApp> {
  final _themeMode = ValueNotifier(ThemeMode.system);

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeModeNotifier(
      notifier: _themeMode,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeMode,
        builder: (context, mode, _) {
          return MultiBlocProvider(
            providers: [
              BlocProvider<HomeBloc>(create: (_) => getIt<HomeBloc>()),
              BlocProvider<HoldingsBloc>(create: (_) => getIt<HoldingsBloc>()),
              BlocProvider<MarketBloc>(create: (_) => getIt<MarketBloc>()),
            ],
            child: MaterialApp.router(
              title: '基金宝',
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode,
              routerConfig: appRouter,
              debugShowCheckedModeBanner: false,
            ),
          );
        },
      ),
    );
  }
}
