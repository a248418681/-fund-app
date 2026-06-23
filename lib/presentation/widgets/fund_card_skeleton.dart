import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

/// 基金列表加载骨架屏
///
/// 用 shimmer 微光效果替代「转圈空白」，首屏加载时展示一组占位卡片，
/// 形状与 [FundCard] 大致对齐，过渡更自然、不突兀。
class FundCardSkeleton extends StatelessWidget {
  const FundCardSkeleton({super.key, this.count = 6});

  /// 占位卡片数量
  final int count;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A3E) : const Color(0xFFEDEDED),
      highlightColor: isDark ? const Color(0xFF3A3A52) : const Color(0xFFF8F8F8),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, __) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(width: 150, height: 15),
                const SizedBox(height: 9),
                _bar(width: 90, height: 11),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bar(width: 70, height: 18),
              const SizedBox(height: 8),
              _bar(width: 48, height: 14),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
