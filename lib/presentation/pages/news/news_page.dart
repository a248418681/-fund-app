import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/fund_entity.dart';
import '../../../domain/repositories/fund_repository.dart';
import '../../../core/di/injection.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, List<NewsItem>> _cachedNews = {};
  final Map<String, String?> _cachedErrors = {};
  bool _loading = true;

  static const _categories = [
    ('102', '快讯'),
    ('103', '股票'),
    ('104', '基金'),
    ('101', '全球'),
    ('105', '商品'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadNews(_categories.first.$1);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final category = _categories[_tabController.index].$1;
    if (!_cachedNews.containsKey(category)) {
      _loadNews(category);
    }
  }

  Future<void> _loadNews(String category) async {
    if (!_cachedNews.containsKey(category)) {
      setState(() => _loading = true);
    }
    try {
      final repo = getIt<FundRepository>();
      final news = await repo.fetchFinanceNews(pageSize: 30, category: category);
      setState(() {
        _cachedNews[category] = news;
        _cachedErrors.remove(category);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[NewsPage] load error: $e');
      setState(() {
        _cachedErrors[category] = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onRefresh(String category) async {
    try {
      final repo = getIt<FundRepository>();
      final news = await repo.fetchFinanceNews(pageSize: 30, category: category);
      setState(() {
        _cachedNews[category] = news;
        _cachedErrors.remove(category);
      });
    } catch (e) {
      debugPrint('[NewsPage] refresh error: $e');
      setState(() { _cachedErrors[category] = e.toString(); });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('财经资讯'),
        backgroundColor: AppTheme.bgSecondary,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: _categories.map((c) => Tab(text: c.$2)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((c) => _buildNewsList(c.$1)).toList(),
      ),
    );
  }

  Widget _buildNewsList(String category) {
    final news = _cachedNews[category];

    if (_loading && news == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _cachedErrors[category];
    if (error != null && (news == null || news.isEmpty)) {
      return _buildErrorView(category, error);
    }

    if (news == null || news.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text('暂无资讯', style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _onRefresh(category),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: news.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, idx) {
          final item = news[idx];
          final isUp = item.title.contains('涨') || item.title.contains('升');
          final isDown = item.title.contains('跌') || item.title.contains('降');
          final tagColor = isUp ? AppTheme.upColor : (isDown ? AppTheme.downColor : AppTheme.textMuted);

          return InkWell(
            onTap: () => _openUrl(item.url),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgSecondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 序号标识
                      Container(
                        width: 4,
                        height: 40,
                        margin: const EdgeInsets.only(right: 10, top: 2),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.digest != null && item.digest!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                item.digest!,
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(item.source, style: const TextStyle(fontSize: 10, color: AppTheme.primary)),
                      ),
                      const SizedBox(width: 8),
                      Text(item.time, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      const Spacer(),
                      Icon(Icons.open_in_new, size: 14, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorView(String category, String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text('加载失败', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              msg,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.6), fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadNews(category),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
