import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/home/home_bloc.dart';
import '../bloc/home/home_event.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';

/// 共享基金搜索底部弹窗（从 home_page / watchlist_page 提取）
class FundSearchSheet extends StatefulWidget {
  const FundSearchSheet({super.key});

  @override
  State<FundSearchSheet> createState() => _FundSearchSheetState();
}

class _FundSearchSheetState extends State<FundSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 拖拽条
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 搜索框
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: '搜索基金代码/名称',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              context.read<SearchBloc>().add(const SearchCleared());
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: AppTheme.bgSecondary,
                  ),
                  onChanged: (value) {
                    context.read<SearchBloc>().add(SearchQueryChanged(value));
                    setState(() {});
                  },
                ),
              ),
              // 结果列表
              Expanded(
                child: BlocBuilder<SearchBloc, SearchState>(
                  builder: (context, state) {
                    if (state.status == SearchStatus.loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state.results.isEmpty) {
                      return Center(
                        child: Text(
                          state.query.isEmpty ? '输入关键词搜索基金' : '未找到相关基金',
                          style: const TextStyle(color: AppTheme.textMuted),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: state.results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final fund = state.results[index];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                            child: Text(
                              fund.code.substring(0, 1),
                              style: const TextStyle(fontSize: 12, color: AppTheme.primary),
                            ),
                          ),
                          title: Text(
                            fund.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${fund.code} · ${fund.type}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
                          onTap: () {
                            context.read<HomeBloc>().add(HomeAddWatchlist(fund.code, fund.name));
                            Navigator.pop(context);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
