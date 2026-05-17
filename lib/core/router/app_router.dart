import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../di/injection.dart';
import '../../presentation/pages/main/main_page.dart';
import '../../presentation/pages/market/market_page.dart';
import '../../presentation/pages/holdings/holdings_page.dart';
import '../../presentation/pages/fund_detail/fund_detail_page.dart';
import '../../presentation/pages/analysis/analysis_page.dart';
import '../../presentation/pages/backtest/backtest_page.dart';
import '../../presentation/pages/compare/compare_page.dart';
import '../../presentation/pages/filter/filter_page.dart';
import '../../presentation/pages/news/news_page.dart';
import '../../presentation/pages/reminder/reminder_page.dart';
import '../../presentation/pages/watchlist/watchlist_page.dart';
import '../../presentation/pages/settings/settings_page.dart';
import '../../presentation/pages/trade/trade_page.dart';
import '../../presentation/bloc/trade/trade_bloc.dart';
import '../../presentation/pages/search/search_page.dart';
import '../../presentation/pages/import/screenshot_import_page.dart';
import '../../presentation/pages/sector_detail/sector_detail_page.dart';
import '../../presentation/bloc/detail/detail_bloc.dart';
import '../../domain/entities/fund_entity.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// 全屏页面淡入+上滑过渡
Page<dynamic> _buildPage(Widget child, {bool opaque = true}) {
  return CustomTransitionPage(
    key: ValueKey(child.hashCode),
    child: child,
    opaque: opaque,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    },
  );
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/holdings',
  routes: [
    // Shell 路由：底部导航 + 4个标签页
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainPage(child: child),
      routes: [
        GoRoute(path: '/holdings', name: 'holdings', builder: (context, state) => const HoldingsPage()),
        GoRoute(path: '/', name: 'home', builder: (context, state) => const WatchlistPage()),
        GoRoute(path: '/market', name: 'market', builder: (context, state) => const MarketPage()),
        GoRoute(path: '/news', name: 'news', builder: (context, state) => const NewsPage()),
      ],
    ),
    // 全屏路由（带过渡动画）
    GoRoute(
      path: '/detail/:code',
      name: 'detail',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(
        BlocProvider(
          create: (_) => getIt<DetailBloc>(),
          child: FundDetailPage(code: state.pathParameters['code']!),
        ),
      ),
    ),
    GoRoute(
      path: '/sector/:code',
      name: 'sectorDetail',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final sector = state.extra as dynamic;
        return _buildPage(
          SectorDetailPage(
            code: state.pathParameters['code']!,
            sector: sector as SectorRankItem?,
          ),
        );
      },
    ),
    GoRoute(
      path: '/trades',
      name: 'trades',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(
        BlocProvider(
          create: (_) => getIt<TradeBloc>(),
          child: TradePage(fundCode: state.uri.queryParameters['code']),
        ),
      ),
    ),
    GoRoute(
      path: '/compare',
      name: 'compare',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const ComparePage()),
    ),
    GoRoute(
      path: '/backtest',
      name: 'backtest',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const BacktestPage()),
    ),
    GoRoute(
      path: '/filter',
      name: 'filter',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const FilterPage()),
    ),
    GoRoute(
      path: '/reminder',
      name: 'reminder',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const ReminderPage()),
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const SearchPage()),
    ),
    GoRoute(
      path: '/import',
      name: 'import',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const ScreenshotImportPage()),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const SettingsPage()),
    ),
    GoRoute(
      path: '/analysis',
      name: 'analysis',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _buildPage(const AnalysisPage()),
    ),
  ],
);
