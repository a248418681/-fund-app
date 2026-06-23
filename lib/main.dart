import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // 恢复主题设置
  final prefs = await SharedPreferences.getInstance();
  final savedThemeIndex = prefs.getInt('theme_mode') ?? 0;
  runApp(FundApp(initialThemeMode: ThemeMode.values[savedThemeIndex]));
}

class FundApp extends StatefulWidget {
  final ThemeMode initialThemeMode;

  const FundApp({super.key, required this.initialThemeMode});

  @override
  State<FundApp> createState() => _FundAppState();
}

class _FundAppState extends State<FundApp> {
  late final ValueNotifier<ThemeMode> _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = ValueNotifier(widget.initialThemeMode);
    _themeMode.addListener(_saveThemeMode);
  }

  Future<void> _saveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', _themeMode.value.index);
  }

  @override
  void dispose() {
    _themeMode.removeListener(_saveThemeMode);
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
