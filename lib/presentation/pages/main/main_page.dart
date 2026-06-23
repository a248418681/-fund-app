import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../bloc/home/home_bloc.dart';
import '../../bloc/holdings/holdings_bloc.dart';
import '../../bloc/market/market_bloc.dart';

class MainPage extends StatefulWidget {
  final Widget child;

  const MainPage({super.key, required this.child});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // BLoC 由 MainPage 统一提供，供子路由使用
  late final HomeBloc _homeBloc;
  late final HoldingsBloc _holdingsBloc;
  late final MarketBloc _marketBloc;

  // 导航顺序：持仓 → 自选 → 行情 → 资讯
  static const _routes = ['/holdings', '/', '/market', '/news'];

  @override
  void initState() {
    super.initState();
    _homeBloc = getIt<HomeBloc>();
    _holdingsBloc = getIt<HoldingsBloc>();
    _marketBloc = getIt<MarketBloc>();
  }

  @override
  void dispose() {
    // BLoC 是 lazySingleton，不在这里关闭，让它们随 app 生命周期存在
    // _homeBloc.close();
    // _holdingsBloc.close();
    // _marketBloc.close();
    super.dispose();
  }

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    // 精确匹配 /（否则 /market 会错误匹配到自选首页）
    final idx = _routes
        .indexWhere((r) => r == '/' ? location == '/' : location.startsWith(r));
    return idx < 0 ? 1 : idx; // 默认选中"自选"（index=1）
  }

  void _onTabSelected(int idx) {
    final currentIdx = _currentIndex(context);
    // 离开持仓 tab → 停止自动刷新
    if (currentIdx == 0 && idx != 0) {
      _holdingsBloc.stopAutoRefresh();
    }
    // 进入持仓 tab → 启动自动刷新
    if (currentIdx != 0 && idx == 0) {
      _holdingsBloc.startAutoRefresh();
    }
    context.go(_routes[idx]);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<HomeBloc>.value(value: _homeBloc),
        BlocProvider<HoldingsBloc>.value(value: _holdingsBloc),
        BlocProvider<MarketBloc>.value(value: _marketBloc),
      ],
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex(context),
          onDestinationSelected: _onTabSelected,
          backgroundColor: AppTheme.bgSecondary,
          indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: '持仓',
            ),
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '自选',
            ),
            NavigationDestination(
              icon: Icon(Icons.trending_up_outlined),
              selectedIcon: Icon(Icons.trending_up),
              label: '行情',
            ),
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article),
              label: '资讯',
            ),
          ],
        ),
      ),
    );
  }
}
