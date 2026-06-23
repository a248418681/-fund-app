import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'ocr_models.dart';
export 'ocr_models.dart';
// OCR 文本解析服务
// V8: 锚点法（纯文本解析）— 旧版，保留兼容
// V9: 横向分析法（2D block坐标解析）— 新版，推荐
// 架构V9：X聚类分列 → Y聚类分行 → 行×列矩阵 → 直接提取字段

/// V8-4.5 推迟的不完整名记录
class _DeferredName {
  final String name; // 不完整基金名（如"嘉实新能源新材料"）
  final double amount; // 已提取的金额
  final int anchorIdx; // 原锚点行索引
  final int? dataLineIdx; // 原数据行索引
  _DeferredName(this.name, this.amount, this.anchorIdx, this.dataLineIdx);
}

class OcrService {
  // ============================================================
  // 关键词列表
  // ============================================================

  // 噪声关键词 — ⚠️ 只放纯广告/文案碎片，不放任何基金后缀/类别词
  // 后缀词（合C/混合C/指数C等）是 OCR 真实输出，放这里会导致数据静默丢失
  static const List<String> _noiseKeywords = [
    '金选指数基金',
    '市场解读',
    '去买入',
    '更多产品',
    '基金经理说',
    '能源替代',
    '清洁能源',
    '油转电',
    '撤退还是加仓',
    '去看看',
    '基金销售服务',
    '化工集体涨停',
    '科创盈利确定性',
  ];

  // ★ V8.1: 资讯标题行过滤 — 支付宝持仓页混入的新闻/资讯文本
  // 特征：含"利好事件""投资锦囊""基金经理说"等前缀，或含|分隔的资讯标题
  static final _infoTitlePattern = RegExp(
    r'(?:^|[|｜])' // 行首或竖线分隔
    r'(?:利好事件|投资锦囊|基金经理说|市场解读|热门资讯|基金排行'
    r'|近\d年|跑赢|高增实|大增\d|增速破|涨幅榜|跌幅榜)'
    r'|→$' // 以箭头结尾
    r'|\|.*?(?:投资|收益|涨|跌|增|跑赢|破\d)', // 含投资关键词的|分隔内容
  );

  // 锚点行过滤：包含这些关键词的 %行 视为噪声（广告/解读文案混入）
  static const List<String> _fundMarketKeywords = [
    '市场解读',
    '基金经理说',
    '地缘扰动',
    '算力',
    '能源替代',
    '油转电',
    '化工集体涨停',
    '科创盈利',
    '撤退还是加仓',
    '需求进一步',
    '涨停',
    '确定性强',
    '业绩披露',
    '基金销售服务',
    '更多产品',
  ];

  // ============================================================
  // 基金公司名关键词（动态加载 + 离线备份）
  // 启动时从东财API拉取全量公司名，替换硬编码列表
  // API: https://fund.eastmoney.com/js/jjjz_gs.js
  // ============================================================

  // 离线备份：API不可用时使用
  static const List<String> _fallbackCompanyNames = [
    '天弘',
    '华夏',
    '广发',
    '南方',
    '博时',
    '银华',
    '大成',
    '兴业',
    '长城',
    '东方',
    '华商',
    '新华',
    '安信',
    '金鹰',
    '银河',
    '长盛',
    '国金',
    '中海',
    '东吴',
    '华宝',
    '华富',
    '中航',
    '永赢',
    '永贏',
    '博道',
    '同泰',
    '恒越',
    '朱雀',
    '中庚',
    '湘财',
    '南华',
    '江信',
    '易方达',
    '嘉实',
    '招商',
    '中欧',
    '工银',
    '华安',
    '鹏华',
    '汇添富',
    '富国',
    '建信',
    '国泰',
    '平安',
    '景顺长城',
    '万家',
    '国海富兰克林',
    '创金合信',
    '中加',
    '泓德',
    '国投瑞银',
    '浦银安盛',
    '上银',
    '中信保诚',
    '鹏扬',
    '农银汇理',
    '圆信永丰',
    '申万菱信',
    '融通',
    '浙商',
    '民生加银',
    '前海开源',
    '诺安',
    '华泰保兴',
    '宝盈',
    '长安',
    '中融',
    '长信',
    '华泰柏瑞',
    '上投摩根',
    '德邦',
    '国联安',
    '光大保德信',
    '海富通',
    '中信建投',
    '摩根士丹利华鑫',
    '汇安',
    '汇丰晋信',
    '太平',
    '泰达宏利',
    '宏利',
    '英大',
    '兴银',
    '中邮创业',
    '诺德',
    '红土创新',
    '财通',
    '中金',
    '西部利得',
    '北信瑞丰',
    '嘉合',
    '格林',
    '睿远',
    '鑫元',
    '恒生前海',
    '金元顺安',
    '西藏东财',
    '东方阿尔法',
    '摩根',
    '云利',
    '生夏',
    '永嘉',
  ];

  // 动态列表（启动时由 initCompanyNames 从API更新）
  static List<String> _fundCompanyNames = _fallbackCompanyNames;

  /// 从东财API加载全量基金公司名，更新 _fundCompanyNames
  /// 应在App启动时调用，失败时保留离线备份
  static Future<void> initCompanyNames() async {
    try {
      // 直接用 http 包拉取，避免依赖 Dio/injection
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('https://fund.eastmoney.com/js/jjjz_gs.js'));
      req.headers.set('User-Agent', 'Mozilla/5.0');
      req.headers.set('Referer', 'https://fund.eastmoney.com/');
      final resp = await req.close();
      final raw = await resp.transform(utf8.decoder).join();
      client.close();
      if (raw.isEmpty) return;

      // 解析 var gs={op:[["ID","公司名"],...]}
      final namePattern = RegExp(r'"(\d+)","([^"]+)"');
      final matches = namePattern.allMatches(raw);
      if (matches.isEmpty) return;

      final shortNames = <String>{};
      for (final m in matches) {
        var name = m.group(2)!;
        // 去掉常见后缀，提取基金产品名中使用的公司短名
        for (final suffix in [
          '基金管理',
          '基金',
          '资产管理',
          '资管',
          '证券(上海)资管',
          '证券资管',
          '证券',
          '(上海)',
          '(中国)'
        ]) {
          name = name.replaceAll(suffix, '');
        }
        name = name.trim();
        if (name.length >= 2) shortNames.add(name);
      }
      // 保留OCR误识变体
      shortNames.addAll({'云利', '生夏', '永嘉', '永贏'});

      // 按长度降序排列（长名优先匹配）
      final sorted = shortNames.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      _fundCompanyNames = sorted;
      debugPrint('[OCR] 公司名列表已从API更新: ${sorted.length} 个');
    } catch (e) {
      debugPrint('[OCR] 公司名API加载失败，使用离线备份: $e');
    }
  }

  // 基金名开头OCR噪声字符（"！？"等）
  static final _nameNoisePrefix = RegExp(r'^[！？?;；:：\s]+');

  static const List<String> _fundSuffixKeywords = [
    'ETF',
    'LOF',
    'QDII',
    '联接',
    '混合',
    '债券',
    '股票',
    '指数',
    '发起式',
    '证券投资基金',
    '基金',
  ];

  // ============================================================
  // V9 主入口：横向分析法（2D block坐标解析）
  // ============================================================

  /// Block 数据结构（从 ML Kit RecognizedText.blocks 提取）
  /// 调用方在 screenshot_import_page.dart 中构建此列表
  static List<RecognizedHolding> parseHoldingBlocks(
    List<OcrBlock> blocks, {
    double imageWidth = 1080,
  }) {
    if (blocks.length < 4) return [];

    debugPrint('[OCR-V9] 输入 ${blocks.length} 个 blocks, imageWidth=$imageWidth');
    // 调试：打印block坐标范围
    if (blocks.isNotEmpty) {
      final maxRight = blocks.map((b) => b.right).reduce(math.max);
      final minLeft = blocks.map((b) => b.left).reduce(math.min);
      debugPrint('[OCR-V9] Block X范围: left=$minLeft ~ right=$maxRight');
      // 打印前10个block的centerX和text
      for (int i = 0; i < blocks.length && i < 10; i++) {
        debugPrint(
            '[OCR-V9]   block[$i] cx=${blocks[i].centerx.toInt()} text="${blocks[i].text.substring(0, blocks[i].text.length > 20 ? 20 : blocks[i].text.length)}"');
      }
    }

    // Step 1: X聚类 → 识别列
    final columns = _v9DetectColumns(blocks, imageWidth);
    if (columns == null || columns.length < 3) {
      debugPrint('[OCR-V9] 列检测失败（${columns?.length ?? 0}列），回退到V8文本解析');
      return [];
    }
    debugPrint('[OCR-V9] 检测到 ${columns.length} 列: '
        '${columns.map((c) => '[${c.left.toStringAsFixed(0)}-${c.right.toStringAsFixed(0)}]').join(' ')}');

    // Step 2: Y聚类 → 识别行
    final rows = _v9DetectRows(blocks);
    debugPrint('[OCR-V9] 检测到 ${rows.length} 行');

    // Step 3: 构建行×列矩阵
    final matrix = _v9BuildMatrix(blocks, rows, columns);

    // Step 4: 从矩阵提取持仓
    final holdings = _v9ExtractHoldings(matrix, rows, columns);

    debugPrint('[OCR-V9] 提取到 ${holdings.length} 条持仓');
    for (int i = 0; i < holdings.length; i++) {
      final h = holdings[i];
      debugPrint(
          '[OCR-V9]   #$i: "${h.name}" amt=${h.amount} yp=${h.yesterdayProfit} hpr=${h.holdingProfitRate}');
    }

    return _deduplicateHoldings(holdings);
  }

  // ============================================================
  // V8 主入口：锚点法（纯文本解析，旧版兼容）
  // ============================================================

  static List<RecognizedHolding> parseHoldingText(String text) {
    final rawLines = text.split('\n');
    final lines = <String>[];
    for (final line in rawLines) {
      final normalized = _normalizeOcrLine(line.trim());
      if (normalized.isNotEmpty) lines.add(normalized);
    }
    if (lines.isEmpty) return [];

    final format = _detectFormat(lines);
    List<RecognizedHolding> holdings;
    switch (format) {
      case ScreenshotFormat.alipay:
        holdings = _parseAlipay(lines);
        break;
      case ScreenshotFormat.tiantian:
        holdings = _parseTiantian(lines);
        break;
      case ScreenshotFormat.generic:
        holdings = _parseGeneric(lines);
        break;
    }
    return _deduplicateHoldings(holdings);
  }

  // ============================================================
  // 格式检测
  // ============================================================

  static ScreenshotFormat _detectFormat(List<String> lines) {
    final text = lines.join(' ');
    final percentLineCount = lines
        .where((l) => RegExp(r'^[+-]\d[\d,]*\.\d{2}%').hasMatch(l.trim()))
        .length;

    // 支付宝特征：%收益率行 + 基金公司名
    final hasFundCompany = RegExp(
            r'(天弘|易方达|招商|平安|华夏|广发|南方|嘉实|富国|博时|中欧|工银|华安|鹏华|汇添富|兴全|景顺长城|交银|建信|银华|中银|国泰|华宝|永赢|同泰|诺德|泓德|恒越|新华|东吴|西部利得|万家|华泰柏瑞|长城|金鹰|申万菱信|长信|融通|国投瑞银|光大保德信|民生加银|浦银安盛|摩根|上投摩根)')
        .hasMatch(text);
    if (text.contains('持有收益率排序') ||
        (text.contains('我的持有') && percentLineCount >= 2) ||
        percentLineCount >= 2 && hasFundCompany ||
        percentLineCount >= 3) {
      return ScreenshotFormat.alipay;
    }
    final codeCount = RegExp(r'\b\d{6}\b').allMatches(text).length;
    if (codeCount >= 3 || text.contains('基金代码') || text.contains('基金名称')) {
      return ScreenshotFormat.tiantian;
    }
    return ScreenshotFormat.generic;
  }

  // ============================================================
  // 支付宝解析器（锚点法 V2 - 真实 OCR 数据驱动）
  //
  // 真实 OCR 规律（4行/基金）：
  //   [0] 基金名主体（可能被分类后缀拆分）
  //   [1] 持有金额（如 "370.38"）
  //   [2] 昨日收益（如 "+41.42"）
  //   [3] %收益率行（如 "+12.59%天弘中证全指通信"）
  //
  // 锚点：%收益率行（^[+-]\d[\d,]*\.\d{2}%）
  // 策略：向前搜索（锚点行之前），找基金名和金额
  // ============================================================

  /// Extract yesterday profit and holding profit from anchor context
  static (double?, double?, double?) _extractProfits(
      String anchorLine, String? dataLine) {
    double? yesterdayProfit;
    double? holdingProfit;
    double? holdingProfitRate;

    // holding profit rate from anchor line
    final rateMatch = RegExp(r'([+-]?\d[\d,]*\.\d{2})%').firstMatch(anchorLine);
    if (rateMatch != null) {
      holdingProfitRate =
          double.tryParse(rateMatch.group(1)!.replaceAll(',', ''));
    }

    // holding profit from anchor line (number before %)
    if (rateMatch != null) {
      final beforePct = anchorLine.substring(0, rateMatch.start).trim();
      final hpMatch = RegExp(r'([+-]\d[\d,]*\.\d{2})$').firstMatch(beforePct);
      if (hpMatch != null) {
        holdingProfit = double.tryParse(hpMatch.group(1)!.replaceAll(',', ''));
      }
    }

    // yesterday profit from data line (number after amount)
    if (dataLine != null && dataLine.isNotEmpty) {
      final amtMatch = RegExp(r'(\d[\d,]*\.\d{2})').firstMatch(dataLine);
      final pmMatches =
          RegExp(r'([+-]\d[\d,]*\.\d{2})').allMatches(dataLine).toList();
      if (amtMatch != null && pmMatches.length >= 2) {
        for (final pm in pmMatches) {
          if (pm.start >= amtMatch.end) {
            yesterdayProfit = double.tryParse(pm.group(1)!.replaceAll(',', ''));
            break;
          }
        }
      }
    }

    return (yesterdayProfit, holdingProfit, holdingProfitRate);
  }

  static List<RecognizedHolding> _parseAlipay(List<String> lines) {
    debugPrint('[OCR-V8] _parseAlipay called with ${lines.length} lines');
    final holdings = <RecognizedHolding>[];
    final usedIndices = <int>{};
    final deferredHolding = <_DeferredName>[]; // V8-4.5 推迟的不完整名
    final suffixFragments =
        <({String name, double amount, int anchorIdx})>[]; // V8.3 后缀碎片

    // V8: 找所有锚点行（含%收益率）
    final anchorIndices = <int>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      // 标准: ±数字.XX% (如 +22.25%, -9.36%)
      if (RegExp(r'[+-]?\d[\d,]*\.\d{2}%').hasMatch(line)) {
        anchorIndices.add(i);
        continue;
      }
      // ★ 增强: 数字 ±数字.XX% (如 3.35 -9.36%)
      // 两个数字，第二个带%号 — 是持有收益+日收益率混合行
      if (RegExp(r'^\d[\d,]*\.\d{2}[+-]\d[\d,]*\.\d{2}%').hasMatch(line)) {
        anchorIndices.add(i);
        continue;
      }
    }

    // ★ 新增: 降级锚点检测 — OCR截断导致%丢失的行（如 "C-1.44+" 或 "指数C-2.096" 或 "+4.39 +1"）
    // 匹配：±数字（含2-3位小数），不以%结尾，前面紧跟中文或)C，或纯数字行
    final fallbackAnchorIndices = <int>[];
    for (int i = 0; i < lines.length; i++) {
      if (anchorIndices.contains(i)) continue;
      final line = lines[i].trim();
      // 匹配: 中文/)/]/C 后紧跟 ±数字.XX（2或3位小数）不以%结尾
      // 例如: "混合C-1.44+", "指数C-2.096" — OCR截断%符号
      // ★ 修复: 前缀长度<=5才视为锚点；长前缀（如"平安高端装备混合-129.33"）是数据行，不是锚点
      final m = RegExp(r'(?:[\u4e00-\u9fa5\))\]]|C)[+-]\d[\d,]*\.\d{2,3}(?!%)')
          .firstMatch(line);
      if (m != null && line.substring(0, m.start).trim().length <= 5) {
        fallbackAnchorIndices.add(i);
        continue;
      }
      // ★ 新增: 纯数字行也作为降级锚点（OCR截断%符号）
      // 例如: "+4.39 +1" — 两个±数字，无中文，无%
      if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(line) &&
          !line.contains('%') &&
          RegExp(r'^[+-]?\d[\d,]*\.\d{2}([+-]\d[\d,]*\.\d{2})?$')
              .hasMatch(line)) {
        fallbackAnchorIndices.add(i);
        continue;
      }
      // ★ 新增: OCR乱码%行（如 "合0 -2.11 占759%" — OCR把"+7.59%"识为"占759%"）
      // 包含 ±数字.XX 且行尾有%号的乱码行
      if (line.contains('%') &&
          RegExp(r'[+-]\d[\d,]*\.\d{2,3}').hasMatch(line) &&
          RegExp(r'[\u4e00-\u9fa5]').hasMatch(line)) {
        fallbackAnchorIndices.add(i);
        continue;
      }
    }

    if (anchorIndices.isEmpty && fallbackAnchorIndices.isEmpty) {
      return _parseGeneric(lines);
    }

    // 合并锚点列表（降级锚点排在后面）
    final allAnchors = <int>[...anchorIndices, ...fallbackAnchorIndices];
    // 降级锚点去重
    allAnchors.sort();

    debugPrint(
        '[OCR-V8] allAnchors: $allAnchors (std=$anchorIndices fallback=$fallbackAnchorIndices)');
    for (int idx = 0; idx < allAnchors.length; idx++) {
      final anchorIdx = allAnchors[idx];
      if (usedIndices.contains(anchorIdx)) continue;

      final anchorLine = lines[anchorIdx].trim();
      debugPrint(
          '[OCR-V8] Anchor idx=$anchorIdx line="$anchorLine" isFallback=${fallbackAnchorIndices.contains(anchorIdx)}');
      final prevAnchor = idx > 0 ? allAnchors[idx - 1] : -1;
      final isFallback = fallbackAnchorIndices.contains(anchorIdx);

      // V8-1: 解析锚点行 — 提取后缀（基金类型后缀 + 剩余名称片段）
      String suffix = '';
      RegExpMatch? rateMatch;
      if (isFallback) {
        // 降级锚点: 如 "C-1.44+" 或 "指数C-2.096"，无%，但有完整±数字
        // 提取第一个±数字之前的文本作为后缀
        final pmMatch = RegExp(r'[+-]\d[\d,]*\.\d{2,3}').firstMatch(anchorLine);
        if (pmMatch != null) {
          var rawSuffix = anchorLine.substring(0, pmMatch.start).trim();
          rawSuffix = rawSuffix.replaceAll(RegExp(r'[,，)）\]]+$'), '');
          suffix = rawSuffix.toUpperCase();
        }
      } else {
        // 正常锚点: 含%
        rateMatch = RegExp(r'([+-]?\d[\d,]*\.\d{2})%').firstMatch(anchorLine);
        if (rateMatch == null) {
          // ★ 兜底: 匹配 '数字 ±数字.XX%' 混合格式（如 3.35 -9.36%）
          final mixedMatch = RegExp(r'\d[\d,]*\.\d{2}([+-]\d[\d,]*\.\d{2})%')
              .firstMatch(anchorLine);
          if (mixedMatch != null) {
            rateMatch = mixedMatch;
          } else {
            usedIndices.add(anchorIdx);
            continue;
          }
        }
        final beforePercent = anchorLine.substring(0, rateMatch.start);
        // 后缀：%前第一个±数字之前的文本
        final beforeClean = beforePercent.replaceAll(RegExp(r'[+-]+$'), '');
        final firstPm = RegExp(r'[+-]\d').firstMatch(beforeClean);
        if (firstPm != null) {
          suffix = beforeClean.substring(0, firstPm.start).trim();
        } else if (beforeClean.trim().isNotEmpty) {
          suffix = beforeClean.trim();
        }
        suffix = suffix.replaceAll(RegExp(r'[,，)）\]]+$'), '');
        suffix = suffix.toUpperCase();
        // 混合格式: '3.35 -9.36%' -> suffix 应为空（3.35是持有收益）
        if (RegExp(r'^\d[\d,]*\.\d{2}$').hasMatch(suffix)) {
          suffix = '';
        }
      }

      // ★ V8-1.5: 噪声锚点处理
      // 如果锚点行 afterPercent 不含任何基金公司名，这是纯噪声锚点
      // 直接反向搜索属于此锚点的基金，跳过 V8-2/V8-3 的常规数据行搜索
      if (!isFallback && rateMatch != null) {
        final afterPercent = anchorLine.substring(rateMatch.end).trim();
        if (afterPercent.isNotEmpty &&
            !_fundCompanyNames.any((c) => afterPercent.contains(c))) {
          // 纯噪声锚点：收集锚点前所有候选行（从远→近的顺序）
          final candidates = <String>[];
          final candIdxs = <int>[];
          for (int k = anchorIdx - 1;
              k > prevAnchor && k >= anchorIdx - 12;
              k--) {
            if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
            final nl = lines[k].trim();
            if (nl.isEmpty || _isNoiseLine(nl) || _isHeaderLine(nl)) continue;
            candidates.insert(0, nl);
            candIdxs.insert(0, k);
          }

          // 分拣基金名（最后一个含公司名的中文行）
          String noiseFund = '';
          int fundCi = -1;
          for (int ci = 0; ci < candidates.length; ci++) {
            if (noiseFund.isEmpty &&
                _fundCompanyNames.any((c) => candidates[ci].contains(c)) &&
                RegExp(r'[\u4e00-\u9fa5]').hasMatch(candidates[ci])) {
              noiseFund = candidates[ci];
              fundCi = ci;
              usedIndices.add(candIdxs[ci]);
            }
          }

          // 分拣金额
          double noiseAmt = 0;
          for (int ci = 0; ci < candidates.length; ci++) {
            if (ci == fundCi) continue;
            final a = _extractAmountFromLine(candidates[ci]);
            if (a != null && a >= 10) {
              noiseAmt = a;
              usedIndices.add(candIdxs[ci]);
              break;
            }
          }

          // 后缀：基金名行之后的所有 class suffix 行
          final noiseSuffixes = <String>[];
          if (fundCi >= 0 && noiseAmt >= 10) {
            for (int ci = fundCi + 1; ci < candidates.length; ci++) {
              if (_isClassSuffix(candidates[ci]) &&
                  !_isNoiseLine(candidates[ci])) {
                noiseSuffixes.add(candidates[ci]);
                usedIndices.add(candIdxs[ci]);
              }
            }
          }

          if (noiseFund.isNotEmpty && noiseAmt >= 10) {
            final clean = _v8Clean(
                noiseFund.replaceAll(RegExp(r'[\-+]\d{1,3}\.\d{2}'), '') +
                    noiseSuffixes.join());
            if (_v8IsValidName(clean) &&
                !holdings.any((h) => _isDuplicateName(h.name, clean))) {
              final (yp, hp, hpr) =
                  _extractProfits(anchorLine, lines[anchorIdx]);
              holdings.add(RecognizedHolding(
                  code: '',
                  name: clean,
                  amount: noiseAmt,
                  yesterdayProfit: yp,
                  holdingProfit: hp,
                  holdingProfitRate: hpr,
                  confidence: 0.5,
                  needsCodeMatch: true));
            }
          }
          usedIndices.add(anchorIdx);
          continue;
        }
      }

      // V8-2: 搜索数据行（锚点前最多5行）
      int? dataLineIdx;
      String fundPrefix = '';
      String nameFrom3Row = '';
      double amount = 0;

      for (int k = anchorIdx - 1; k > prevAnchor && k >= anchorIdx - 5; k--) {
        if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
        final line = lines[k].trim();
        if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
        if (_isPureProfitLine(line)) continue;

        // ★ 修复: 处理负数金额如 "混合C-129.33" → 匹配 129.33
        // 排除紧跟在 -+ 或 数字 后面的匹配（防止部分数字被误匹配）
        // ★ 修复: 匹配金额（含负数），取绝对值判断
        final amountMatch = RegExp(r'[-]?(\d[\d,]*\.\d{2})').firstMatch(line);
        if (amountMatch != null) {
          final parsed = _parseAmount(amountMatch.group(1)!).abs();
          if (parsed >= 10) {
            dataLineIdx = k;
            // ★ 修复: 去掉 fundPrefix 末尾的 -+ 符号，防止拼接 suffix 时出现 "混合Cc"
            var fp = line.substring(0, amountMatch.start).trim();
            fp = fp.replaceAll(RegExp(r'[+]+$'), '');
            fp = fp.replaceAll(RegExp(r'c$'), 'C'); // 统一小写c
            fundPrefix = fp;
            amount = parsed;
            break;
          }
        }
      }

      // V8-2b: 兜底搜索（数据行搜索失败 或 fundPrefix为空时）
      // ★ 已删除 V8-2b-1（向下搜）— 支付宝截图基金名永远在锚点上方，向下搜会偷下一个基金的行
      if (dataLineIdx == null || fundPrefix.isEmpty) {
        // V8-2b-1b: 向前找基金名（锚点上方，正常方向）
        {
          for (int k = anchorIdx - 1;
              k > prevAnchor && k >= anchorIdx - 6;
              k--) {
            if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
            final line = lines[k].trim();
            if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) {
              continue;
            }
            if (_fundCompanyNames.any((c) => line.contains(c))) {
              // 提取基金名：去掉行内金额（如"广发远见智选混合 656.20"→"广发远见智选混合"）
              final amountMatch =
                  RegExp(r'[-]?(\d[\d,]*\.\d{2})').firstMatch(line);
              if (amountMatch != null) {
                nameFrom3Row = line.substring(0, amountMatch.start).trim();
                final parsed = _parseAmount(amountMatch.group(1)!).abs();
                if (parsed >= 10) {
                  amount = parsed;
                  dataLineIdx = k;
                }
              } else {
                nameFrom3Row = line; // 纯名称行，无金额
              }
              break;
            }
          }
        }
        // V8-2b-2: 向前找金额或持有收益（用于估算）
        int? amountOnlyIdx;
        for (int k = anchorIdx - 1; k > prevAnchor && k >= anchorIdx - 6; k--) {
          if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
          if (k == dataLineIdx) continue; // 跳过已处理的基金名行
          final line = lines[k].trim();
          if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) {
            continue;
          }
          final m = RegExp(r'^([+-]?\d[\d,]*\.\d{2})([+-]\d[\d,]*\.\d{2})?$')
              .firstMatch(line);
          if (m != null) {
            final val = _parseAmount(m.group(1)!).abs();
            if (val >= 10) {
              amountOnlyIdx = k;
              dataLineIdx = k;
              amount = val.abs(); // 取绝对值（持有收益可能是负数）
              break;
            }
          }
        }
        // V8-2b-3: 如果没有单独金额，尝试从锚点行提取持有收益
        if (amount < 10 && nameFrom3Row.isNotEmpty && rateMatch != null) {
          final afterPercent = anchorLine.substring(rateMatch.end).trim();
          final hpMatch =
              RegExp(r'([+-]?\d[\d,]*\.\d{2})').firstMatch(afterPercent);
          if (hpMatch != null) {
            amount = _parseAmount(hpMatch.group(1)!).abs();
          }
        }
        // V8-2b-4: 如果找到了基金名，且有金额或持有收益
        if (nameFrom3Row.isNotEmpty && amount >= 10) {
          String raw = nameFrom3Row + suffix;
          final cleanName = _v8Clean(raw);
          // ★ 不完整名检查：缺类别后缀→推迟到 Phase 1.5/2.5 拼接
          final hasTypeSuffix =
              RegExp(r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强)[A-C]?$')
                  .hasMatch(cleanName);
          if (_v8IsValidName(cleanName) && hasTypeSuffix) {
            final isDup =
                holdings.any((h) => _isDuplicateName(h.name, cleanName));
            if (!isDup) {
              final (yp, hp, hpr) = _extractProfits(
                  anchorLine, dataLineIdx != null ? lines[dataLineIdx] : null);
              holdings.add(RecognizedHolding(
                code: '', name: cleanName, amount: amount,
                yesterdayProfit: yp, holdingProfit: hp, holdingProfitRate: hpr,
                confidence: amount >= 100 ? 0.7 : 0.5, // 低金额降低置信度
                needsCodeMatch: true,
              ));
            }
            usedIndices.add(anchorIdx);
            if (amountOnlyIdx != null) usedIndices.add(amountOnlyIdx);
            continue; // 已处理，跳到下一个锚点
          }
          // 名字不完整（缺后缀），跳过此锚点，留给 Phase 1.5/2.5
          debugPrint(
              '[OCR-V8] V8-2b-4: incomplete name "$cleanName", deferring to Phase 1.5/2.5');
        }
        // ★ V8-2c: fallback anchor 最终兜底
        debugPrint(
            '[OCR-V8] V8-2c check: isFallback=$isFallback amount=$amount nameFrom3Row="$nameFrom3Row" dataLineIdx=$dataLineIdx');
        if (isFallback && amount < 10 && nameFrom3Row.isEmpty) {
          final selfAmt =
              _parseAmount(anchorLine.replaceAll(RegExp(r'[^\d\.-]'), ''))
                  .abs();
          debugPrint(
              '[OCR-V8] V8-2c: selfAmt=$selfAmt, searching range ${(prevAnchor > anchorIdx - 8 ? prevAnchor : anchorIdx - 8)}..${anchorIdx - 1}');
          if (selfAmt >= 10) {
            for (int k = anchorIdx - 1;
                k > prevAnchor && k >= anchorIdx - 8;
                k--) {
              if (usedIndices.contains(k) ||
                  anchorIndices.contains(k) ||
                  fallbackAnchorIndices.contains(k)) {
                debugPrint(
                    '[OCR-V8] V8-2c: skip idx=$k (used/anchor/fallback)');
                continue;
              }
              final line = lines[k].trim();
              debugPrint('[OCR-V8] V8-2c: inspect idx=$k line="$line"');
              if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) {
                continue;
              }
              final hasCompany = _fundCompanyNames.any((c) => line.contains(c));
              final hasChinese = RegExp(r'[\u4e00-\u9fa5]{4,}').hasMatch(line);
              debugPrint(
                  '[OCR-V8] V8-2c: idx=$k hasCompany=$hasCompany hasChinese=$hasChinese');
              if (hasCompany && hasChinese) {
                final clean = _v8Clean(line + suffix);
                final hasTypeSuffix =
                    RegExp(r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强)[A-C]?$')
                        .hasMatch(clean);
                if (_v8IsValidName(clean) &&
                    hasTypeSuffix &&
                    !holdings.any((h) => _isDuplicateName(h.name, clean))) {
                  final (yp, hp, hpr) = _extractProfits(anchorLine, null);
                  holdings.add(RecognizedHolding(
                    code: '',
                    name: clean,
                    amount: selfAmt,
                    yesterdayProfit: yp,
                    holdingProfit: hp,
                    holdingProfitRate: hpr,
                    confidence: 0.5,
                    needsCodeMatch: true,
                  ));
                  debugPrint(
                      '[OCR-V8] V8-2c fallback rescue: "$clean" amt=$selfAmt from anchor idx=$anchorIdx');
                  usedIndices.add(anchorIdx);
                  usedIndices.add(k);
                  break;
                } else if (_v8IsValidName(clean)) {
                  // 有公司名但缺类型后缀 → 存入 deferredHolding 交给 Phase 2.6 补全
                  debugPrint(
                      '[OCR-V8] V8-2c deferred (no suffix): "$clean" amt=$selfAmt from anchor idx=$anchorIdx');
                  deferredHolding
                      .add(_DeferredName(clean, selfAmt, anchorIdx, k));
                  usedIndices.add(anchorIdx);
                  usedIndices.add(k);
                  break;
                }
              } else if (hasChinese && !hasCompany && line.length >= 6) {
                // ★ Unicode 变体导致公司名匹配失败（如 永贏 vs 永赢）
                // 仍有足够中文内容 → 存入 deferredHolding 交给 Phase 2.6
                final clean = _v8Clean(line + suffix);
                if (_v8IsValidName(clean) &&
                    !holdings.any((h) => _isDuplicateName(h.name, clean))) {
                  debugPrint(
                      '[OCR-V8] V8-2c deferred (unicode variant): "$clean" amt=$selfAmt from anchor idx=$anchorIdx');
                  deferredHolding
                      .add(_DeferredName(clean, selfAmt, anchorIdx, k));
                  usedIndices.add(anchorIdx);
                  usedIndices.add(k);
                  break;
                }
              }
            }
            continue; // 无论是否成功都跳过（防止重复）
          }
        }

        // 纯金额行兜底也没找到，跳过此锚点
        usedIndices.add(anchorIdx);
        continue;
      }

      debugPrint(
          '[OCR-V8] V8-2 result: dataLineIdx=$dataLineIdx fundPrefix="$fundPrefix" amount=$amount nameFrom3Row="$nameFrom3Row"');
      // V8-3: fundPrefix为空时的多策略补全
      if (fundPrefix.isEmpty) {
        // V8-3a: 直接在锚点上方搜含公司名的行（优先，处理"金额行"+"基金名"+"锚点"格式）
        if (nameFrom3Row.isEmpty) {
          for (int k = anchorIdx - 1;
              k > prevAnchor && k >= anchorIdx - 5;
              k--) {
            if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
            final line = lines[k].trim();
            if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) {
              continue;
            }
            if (_fundCompanyNames.any((c) => line.contains(c))) {
              nameFrom3Row = line;
              debugPrint('[OCR-V8] V8-3a found company line at $k: "$line"');
              break;
            }
          }
        }
        // V8-3b: 纯数字行格式（原逻辑）
        if (nameFrom3Row.isEmpty) {
          int? pureNumIdx;
          for (int k = anchorIdx - 1;
              k > prevAnchor && k >= anchorIdx - 6;
              k--) {
            if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
            final line = lines[k].trim();
            if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) {
              continue;
            }
            if (RegExp(r'^[\d.+-]+$').hasMatch(line)) {
              pureNumIdx = k;
              break;
            }
          }
          if (pureNumIdx != null) {
            bool found = false;
            for (int k = pureNumIdx - 1;
                k > prevAnchor && k >= pureNumIdx - 2;
                k--) {
              if (usedIndices.contains(k) || anchorIndices.contains(k)) {
                continue;
              }
              final line = lines[k].trim();
              if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) {
                continue;
              }
              if (_fundCompanyNames.any((c) => line.contains(c))) {
                nameFrom3Row = line;
                found = true;
                break;
              }
            }
            if (!found) {
              for (int k = pureNumIdx + 1;
                  k < lines.length && k <= pureNumIdx + 2;
                  k++) {
                if (usedIndices.contains(k) || anchorIndices.contains(k)) {
                  continue;
                }
                final line = lines[k].trim();
                if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) {
                  continue;
                }
                if (_fundCompanyNames.any((c) => line.contains(c))) {
                  nameFrom3Row = line;
                  break;
                }
              }
            }
          }
        }
      }

      // V8-4: 组装基金名
      String raw = fundPrefix + suffix;
      debugPrint('[OCR-V8] V8-4: suffix="$suffix" raw="$raw"');
      if (!_v8IsValidName(_v8Clean(raw)) && nameFrom3Row.isNotEmpty) {
        raw = nameFrom3Row + suffix;
      }
      final cleanName = _v8Clean(raw);

      // V8-4.5: 名字缺少类别后缀 → 推迟到 Phase 2.5 拼接
      // 支付宝 OCR 经常把基金名拆成两行（如"嘉实新能源新材料"+"混合C"）
      // 不完整名不应该进入 V8-6，否则 Phase 2.5 找不到可用行
      // ★ 正则需包容 OCR 误识（指教→指数）和括号内容（联接(LOF)C、指数(QDI-LOF)A）
      final hasTypeSuffix = RegExp(
              r'(混合|混台|指数|指教|股票|债券|ETF|LOF|QDII|QDI|联接|增强|优选)(\([^)]*\))?[A-C]?$')
          .hasMatch(cleanName);
      if (!hasTypeSuffix) {
        debugPrint(
            '[OCR-V8] V8-4.5: "$cleanName" missing type suffix, deferring to Phase 2.5');
        usedIndices.add(anchorIdx);
        usedIndices.add(dataLineIdx); // ★ 标 used 防 Phase 1.5 垃圾
        // 存入延迟列表，供 Phase 2.6 补全
        deferredHolding
            .add((_DeferredName(cleanName, amount, anchorIdx, dataLineIdx)));
        continue; // 跳到下一个锚点
      }

      // V8-5: 验证
      if (!_v8IsValidName(cleanName)) {
        // ★ V8.3: 后缀碎片（无公司前缀但有类型词）→ 存入 suffixFragments 待合并
        // 但如果名字含公司前缀，说明是完整基金名缺A/C后缀，不应当碎片
        final hasCompanyPrefix =
            _fundCompanyNames.any((c) => cleanName.startsWith(c));
        if (!hasCompanyPrefix &&
            RegExp(r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强|优选|量化)(\([^)]*\))?[A-Ca-c]?$')
                .hasMatch(cleanName)) {
          suffixFragments
              .add((name: cleanName, amount: amount, anchorIdx: anchorIdx));
          debugPrint(
              '[OCR-V8] V8-5: suffix fragment "$cleanName" amt=$amount saved for merge');
        } else if (hasCompanyPrefix) {
          // 有公司名但验证失败（通常缺A/C后缀），保留为holding + needsCodeMatch
          debugPrint(
              '[OCR-V8] V8-5: valid company name but incomplete "$cleanName" amt=$amount, keeping with needsCodeMatch');
          holdings.add(RecognizedHolding(
            code: '',
            name: cleanName,
            amount: amount,
            confidence: 0.5,
            needsCodeMatch: true,
          ));
        }
        usedIndices.add(anchorIdx);
        continue;
      }
      if (amount < 10) {
        usedIndices.add(anchorIdx);
        continue;
      }

      // ★ V8.2: 缺 A/C 后缀 → 尝试向下 1-2 行找独立的 C/A 字母
      var finalName = cleanName;
      if (RegExp(r'(混合|指数|指教|股票|债券|ETF|LOF|QDII|联接|增强|优选|混台)[A-Ca-c]?$')
              .hasMatch(cleanName) &&
          !RegExp(r'(混合|指数|指教|股票|债券|ETF|LOF|QDII|联接|增强|优选|混台)[A-C]$')
              .hasMatch(cleanName)) {
        for (int k = anchorIdx + 1;
            k < lines.length && k <= anchorIdx + 3;
            k++) {
          if (usedIndices.contains(k)) continue;
          final nextL = lines[k].trim();
          if (RegExp(r'^[A-Ca-c]$').hasMatch(nextL)) {
            finalName = cleanName + nextL.toUpperCase();
            debugPrint(
                '[OCR-V8] V8-5: appended suffix "$nextL" → "$finalName"');
            break;
          }
        }
      }

      // V8-6: 去重 & 添加
      final isDup = holdings.any((h) => _isDuplicateName(h.name, finalName));
      if (!isDup) {
        final dataLineText = lines[dataLineIdx];
        final (yp, hp, hpr) = _extractProfits(anchorLine, dataLineText);
        holdings.add(RecognizedHolding(
          code: '',
          name: finalName,
          amount: amount,
          yesterdayProfit: yp,
          holdingProfit: hp,
          holdingProfitRate: hpr,
          confidence: 0.7,
          needsCodeMatch: true,
        ));
      }

      usedIndices.add(anchorIdx);
      usedIndices.add(dataLineIdx);
    }

    debugPrint('[OCR-V8] Entering Phase 1.5 (inter-anchor recovery)...');
    // ===== Phase 1.5: 锚点间遗漏基金恢复 =====
    // 处理位于两个锚点之间、无专属锚点的基金
    // 如 "嘉实新能源新材料" 夹在噪声锚点与有效锚点之间，其数据行被上一锚点占用
    for (int i = 0; i < lines.length; i++) {
      if (usedIndices.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
      if (!_fundCompanyNames.any((c) => line.contains(c))) continue;
      // ★ V8.1: 资讯标题含公司名但不是基金名（如"南方电网一季度投资大增49.5%"）
      if (_infoTitlePattern.hasMatch(line)) continue;
      if (_isPureAmountLine(line) || _isPureProfitLine(line)) continue;

      double? amt;
      final suffixes = <String>[];
      // 先向下搜索后缀和金额
      for (int j = i + 1; j < lines.length && j <= i + 12; j++) {
        final nl = lines[j].trim();
        if (_isNoiseLine(nl) || _isHeaderLine(nl)) break;
        // 锚点行或另一基金名行 → 停止搜索
        if (RegExp(r'^[+-]\d[\d,]*\.\d{2}%').hasMatch(nl)) break;
        if (_fundCompanyNames.any((c) => nl.contains(c))) break;
        // 金额行
        if (amt == null) {
          final a = _extractAmountFromLine(nl);
          if (a != null && a >= 10) {
            amt = a;
            continue;
          }
        }
        // 后缀行（先strip | 前缀）
        final nlClean = nl.replaceFirst(RegExp(r'^[|\\s]+'), '');
        // ★ V8.2: 跳过含乱码的后缀行（日文假名/龐國@等）
        if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF龜國@]{1,}').hasMatch(nlClean)) {
          continue;
        }
        // ★ V8.2: 跳过含“指数教基金國”等拼接垃圾的后缀
        if (RegExp(r'(指数|指教)教|基金國|基金区').hasMatch(nlClean)) continue;
        if (_isClassSuffix(nlClean)) {
          suffixes.add(nlClean);
          continue;
        }
        // 纯数字收益行
        if (RegExp(r'^[+-]?\d[\d,]*\.\d{2}$').hasMatch(nl)) continue;
        // 找到金额后的非预期行 → 结束
        if (amt != null) break;
      }
      // 向上搜索金额（处理金额行在基金名上方的情况）
      if (amt == null) {
        for (int j = i - 1; j >= 0 && j >= i - 5; j--) {
          if (usedIndices.contains(j)) continue;
          final nl = lines[j].trim();
          if (nl.isEmpty || _isNoiseLine(nl) || _isHeaderLine(nl)) continue;
          final a = _extractAmountFromLine(nl);
          if (a != null && a >= 10) {
            amt = a;
            break;
          }
          if (_fundCompanyNames.any((c) => nl.contains(c))) break;
        }
      }

      if (amt != null && amt >= 10) {
        // 清洗名字：去掉行内金额（\d+\.\d{2}）和带符号收益（±\d+.\d{2}）
        final nameOnly =
            line.replaceAll(RegExp(r'[\-+]?\d[\d,]*\.\d{2}'), '').trim();
        // ★ V8.3: 放宽后缀验证 — 改用「拼接后整体验证」方式
        // 之前逐个后缀白名单匹配太严，"设备指数A"等被拒
        final validSuffixes = <String>[];
        for (final suf in suffixes) {
          final sufClean = _v8Clean(suf);
          // 跳过乱码/垃圾
          if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF龜國@]').hasMatch(sufClean)) {
            continue;
          }
          if (RegExp(r'(指数|指教)教|基金國|基金区').hasMatch(sufClean)) continue;
          // 方法：拼接后看整体是否含类型词+份额后缀
          final trial = _v8Clean(nameOnly + sufClean);
          if (RegExp(
                  r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强|优选|量化)(\([^)]*\))?[A-Ca-c]?$')
              .hasMatch(trial)) {
            validSuffixes.add(sufClean);
          }
        }
        final clean = _v8Clean(nameOnly + validSuffixes.join());
        debugPrint(
            '[OCR-V8] Phase 1.5 found: "$clean" amt=$amt suffixes=$suffixes validSuffixes=$validSuffixes');
        if (_v8IsValidName(clean) &&
            !holdings.any((h) => _isDuplicateName(h.name, clean))) {
          final (yp, hp, hpr) = _extractProfits(lines[i], null);
          // ★ V8.2: 缺 A/C 后缀时，尝试向下1-2行找独立 A/C
          var finalName = clean;
          if (RegExp(r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强)[A-Ca-c]?$')
                  .hasMatch(clean) &&
              !RegExp(r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强)[A-C]$')
                  .hasMatch(clean)) {
            // 名字以类型词结尾但缺 A/C
            for (int jj = i + 1; jj < lines.length && jj <= i + 3; jj++) {
              if (usedIndices.contains(jj)) continue;
              final nextL = lines[jj].trim();
              if (RegExp(r'^[A-Ca-c]$').hasMatch(nextL)) {
                finalName = clean + nextL.toUpperCase();
                debugPrint(
                    '[OCR-V8] Phase 1.5: appended suffix "$nextL" → "$finalName"');
                break;
              }
            }
          }
          // ★ 缺类型后缀时存入 deferredHolding 交给 Phase 2.6 补全
          final hasTypeSuffix =
              RegExp(r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强)[A-C]?$')
                  .hasMatch(finalName);
          if (!hasTypeSuffix) {
            debugPrint(
                '[OCR-V8] Phase 1.5: deferring "$finalName" (no type suffix) to Phase 2.6');
            deferredHolding.add(_DeferredName(finalName, amt, i, i));
          } else {
            holdings.add(RecognizedHolding(
                code: '',
                name: finalName,
                amount: amt,
                yesterdayProfit: yp,
                holdingProfit: hp,
                holdingProfitRate: hpr,
                confidence: 0.5,
                needsCodeMatch: true));
          }
        } else if (_v8IsValidName(clean) == false &&
            validSuffixes.isEmpty &&
            RegExp(r'[\u4e00-\u9fa5]{4,}').hasMatch(clean)) {
          // ★ V8.2: 即使名字不完整（缺后缀），只要有4+汉字且含公司名，也加入 needsCodeMatch
          // 这样后端基金代码匹配可以补全名字
          final baseClean = _v8Clean(nameOnly);
          if (_v8IsValidName(baseClean) ||
              (_fundCompanyNames.any((c) => baseClean.contains(c)) &&
                  baseClean.length >= 6)) {
            debugPrint(
                '[OCR-V8] Phase 1.5: incomplete but salvageable "$baseClean", deferring to Phase 2.6');
            deferredHolding.add(_DeferredName(baseClean, amt, i, i));
          }
        }
        usedIndices.add(i);
      }
    }

    // ===== Phase 1.6: 纯数字行锚点兜底 =====
    // 处理支付宝底部基金的纯数字锚点（如 "+0.96"），在锚点前向上搜索基金名+金额
    for (int i = 0; i < lines.length; i++) {
      if (usedIndices.contains(i)) continue;
      final line = lines[i].trim();
      // 纯数字行（非锚点格式：非 ±数字% 也非 ±数字±数字%）
      if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(line)) continue;
      if (line.contains('%')) continue;
      if (!RegExp(r'^[+-]?\d[\d,]*\.\d{2}(?:[+-]\d[\d,]*\.\d{2})?$')
          .hasMatch(line)) {
        continue;
      }

      // 向前搜索基金名+金额
      String? fundName;
      double? amt;
      for (int k = i - 1; k >= 0 && k >= i - 12; k--) {
        if (usedIndices.contains(k)) continue;
        final nl = lines[k].trim();
        if (nl.isEmpty || _isNoiseLine(nl) || _isHeaderLine(nl)) continue;
        if (RegExp(r'^[+-]\d[\d,]*\.\d{2}%').hasMatch(nl)) break;
        if (_fundCompanyNames.any((c) => nl.contains(c)) &&
            !_isPureAmountLine(nl) &&
            !_isPureProfitLine(nl)) {
          fundName ??= nl;
          final a = _extractAmountFromLine(nl);
          if (a != null && a >= 10 && amt == null) amt = a;
          continue;
        }
        final a = _extractAmountFromLine(nl);
        if (a != null && a >= 10 && amt == null) {
          amt = a;
          if (fundName == null) {
            for (int pk = k - 1; pk >= 0 && pk >= k - 4; pk--) {
              final pn = lines[pk].trim();
              if (_fundCompanyNames.any((c) => pn.contains(c)) &&
                  !_isPureAmountLine(pn) &&
                  !_isPureProfitLine(pn)) {
                fundName = pn;
                break;
              }
            }
          }
        }
      }

      if (fundName != null && amt != null && amt >= 10) {
        final clean = _v8Clean(fundName);
        if (_v8IsValidName(clean) &&
            !holdings.any((h) => _isDuplicateName(h.name, clean))) {
          final (yp, hp, hpr) = _extractProfits(line, null);
          holdings.add(RecognizedHolding(
              code: '',
              name: clean,
              amount: amt,
              yesterdayProfit: yp,
              holdingProfit: hp,
              holdingProfitRate: hpr,
              confidence: 0.5,
              needsCodeMatch: true));
        }
        usedIndices.add(i);
      }
    }

    // ===== Phase 2: 后缀行兜底 =====
    // 处理 OCR 右列极端截断导致 % 完全丢失的情况
    // 例如: "广发远见智选混合646.75+117.79" 后跟 "C-1.44+"
    for (int i = 0; i < lines.length - 1; i++) {
      if (usedIndices.contains(i)) continue;
      final dl = lines[i].trim();
      if (dl.isEmpty || _isNoiseLine(dl) || _isHeaderLine(dl)) continue;
      final amt = _extractAmountFromLine(dl);
      if (amt == null || amt < 10) continue;
      if (!_fundCompanyNames.any((c) => dl.contains(c))) continue;

      final nextLine = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
      if (!_isSuffixLine(nextLine) &&
          !RegExp(r'^(?:ETF联接|QDII|LOF)[A-C]?(?:\([A-Z]+\))?[A-C]?$')
              .hasMatch(nextLine)) {
        continue;
      }

      // 提取数据行前缀（金额之前的部分）
      final amountMatch = RegExp(r'[-]?(\d[\d,]*\.\d{2})').firstMatch(dl);
      if (amountMatch == null) continue;
      final prefix = dl.substring(0, amountMatch.start).trim();

      // 提取后缀文本（第一个±数字之前）
      final pmMatch = RegExp(r'[+-]\d').firstMatch(nextLine);
      var suffix = pmMatch != null
          ? nextLine.substring(0, pmMatch.start).trim()
          : nextLine;
      suffix = suffix.replaceAll(RegExp(r'[,，)）\]]+$'), '');

      final rawName = prefix + suffix;
      final cleanName = _v8Clean(rawName);

      if (_v8IsValidName(cleanName) && amt >= 10) {
        final (yp, hp, hpr) = _extractProfits(lines[i], dl);
        holdings.add(RecognizedHolding(
          code: '',
          name: cleanName,
          amount: amt,
          yesterdayProfit: yp,
          holdingProfit: hp,
          holdingProfitRate: hpr,
          confidence: 0.5,
          needsCodeMatch: true,
        ));
        usedIndices.add(i);
        usedIndices.add(i + 1);
      }
    }

    debugPrint('[OCR-V8] Entering Phase 2.5 (cross-line name join)...');
    // ===== Phase 2.5: 跨行基金名后缀拼接兜底 =====
    // 处理 MLKit 将基金名拆成两行的情况
    // 例如: "博道上证科创板综" + "合指数增强C 332.81"
    for (int i = 0; i < lines.length - 1; i++) {
      if (usedIndices.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
      if (!_fundCompanyNames.any((c) => line.contains(c))) continue;
      // 检查当前行是否以不完整词结尾（如"综"、"装"、"健"）
      final incompleteEndings = [
        '综',
        '装',
        '健',
        '联',
        '连',
        '增',
        '成',
        '新',
        '造',
        '技',
        '选',
        '工',
        '资',
        '先',
        '料',
        '赢'
      ];
      if (!incompleteEndings.any((e) => line.endsWith(e))) continue;

      // 向后搜索拼接行
      for (int j = i + 1; j < lines.length && j <= i + 3; j++) {
        if (usedIndices.contains(j)) continue;
        final nl = lines[j].trim();
        if (nl.isEmpty || _isNoiseLine(nl) || _isHeaderLine(nl)) break;
        // ★ V8.1: 含日文乱码的行不应作为拼接源
        if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF龜國@]{2,}').hasMatch(nl)) break;

        // 检查下一行是否以基金类型词开头（先去掉行首|等噪声）
        final nlClean = nl.replaceFirst(RegExp(r'^[|\\s]+'), '');
        final typeWords = [
          '合',
          '台',
          '指数',
          '主题',
          '混合',
          'ETF',
          '债券',
          '股票',
          '联接',
          '量化',
          '増强',
          '增强',
          '先锋',
          '健康',
          '优选',
          '制造'
        ];
        if (!typeWords.any((w) => nlClean.startsWith(w))) break;

        // 拼接基金名（用清理后的行）
        final combinedName = line +
            nlClean.replaceAll(RegExp(r'[+-]?\d[\d,]*\.\d{2}.*'), '').trim();
        final clean = _v8Clean(combinedName);

        // 从拼接行或再下一行提取金额
        double? amt;
        final amtFromNext = _extractAmountFromLine(nl);
        if (amtFromNext != null && amtFromNext >= 10) {
          amt = amtFromNext;
        } else if (j + 1 < lines.length) {
          final amtFromBelow = _extractAmountFromLine(lines[j + 1].trim());
          if (amtFromBelow != null && amtFromBelow >= 10) {
            amt = amtFromBelow;
            usedIndices.add(j + 1);
          }
        }
        // 向上搜索金额（处理金额行在基金名上方的情况）
        if (amt == null) {
          for (int k = i - 1; k >= 0 && k >= i - 5; k--) {
            if (usedIndices.contains(k)) continue;
            final aboveLine = lines[k].trim();
            if (aboveLine.isEmpty ||
                _isNoiseLine(aboveLine) ||
                _isHeaderLine(aboveLine)) {
              continue;
            }
            final a = _extractAmountFromLine(aboveLine);
            if (a != null && a >= 10) {
              amt = a;
              break;
            }
            if (_fundCompanyNames.any((c) => aboveLine.contains(c))) break;
          }
        }

        if (amt != null && amt >= 10 && _v8IsValidName(clean)) {
          final isDup = holdings.any((h) => _isDuplicateName(h.name, clean));
          if (!isDup) {
            final (yp, hp, hpr) = _extractProfits(lines[i], null);
            holdings.add(RecognizedHolding(
              code: '',
              name: clean,
              amount: amt,
              yesterdayProfit: yp,
              holdingProfit: hp,
              holdingProfitRate: hpr,
              confidence: 0.5,
              needsCodeMatch: true,
            ));
            usedIndices.add(i);
            usedIndices.add(j);
          }
        }
        break; // 只看第一行拼接候选
      }
    }

    // ===== Phase 2.6: 补全 V8-4.5 推迟的不完整名 =====
    // 从锚点后搜索后缀行（如"锋混合C"、"产业主题ETF联接C"），拼回完整名
    for (final d in deferredHolding) {
      // 跳过明显非基金名的推迟项（如纯数字 "-1.8"）
      if (!_fundCompanyNames.any((c) => d.name.contains(c)) &&
          !RegExp(r'[\u4e00-\u9fff]{2,}').hasMatch(d.name)) {
        continue;
      }

      // 从锚点行向下搜索最多8行，找含基金类型词的行
      for (int j = d.anchorIdx + 1;
          j < lines.length && j <= d.anchorIdx + 8;
          j++) {
        if (usedIndices.contains(j)) continue;
        final nextLine = lines[j].trim().replaceFirst(RegExp(r'^[|\\s]+'), '');
        if (nextLine.isEmpty) continue;
        // ★ V8.1: 资讯标题行跳过
        if (_isNoiseLine(nextLine)) continue;
        // 后缀行含基金类型词（用 contains 比 startsWith 更灵活，OCR后缀行可能不以类型词开头）
        final typeWords = [
          '混合',
          '混台',
          '指数',
          '指教',
          'ETF',
          '联接',
          '股票',
          '债券',
          '量化',
          '増强',
          '增强',
          '先锋',
          '优选',
          '制造',
          '主题',
          '产业',
          '金属',
          '锋',
          '康',
          '合',
          '台'
        ];
        if (!typeWords.any((w) => nextLine.contains(w))) continue;
        // 后缀行不应是另一个完整基金名（含公司名+类型词+ABCS后缀）
        final isFullFundName =
            _fundCompanyNames.any((c) => nextLine.contains(c)) &&
                RegExp(r'(混合|指数|ETF|股票|债券|联接)[ABC]?$').hasMatch(
                    nextLine.replaceAll(RegExp(r'[+-]?\d[\d,]*\.\d{2}.*'), ''));
        if (isFullFundName) continue;
        // 拼接：从后缀行提取纯名称部分（去掉金额和收益数据）
        var suffixPart = nextLine
            .replaceAll(RegExp(r'[+-]?\d[\d,]*\.\d{2}.*'), '') // 去金额/收益
            .replaceAll(RegExp(r'^\d+[,.]\d+.*'), '') // 去纯数字行残余
            .trim();
        // 如果后缀行去金额后为空，尝试保留到第一个数字之前的部分
        if (suffixPart.isEmpty) {
          final beforeNum = RegExp(r'^(.*?)[+-]?\d').firstMatch(nextLine);
          if (beforeNum != null) suffixPart = beforeNum.group(1)!.trim();
        }
        // ★ V8.1: 后缀行乱码检测 — 含日文假名/特殊符号的行是垃圾拼接源
        if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF龜國@]{2,}').hasMatch(nextLine)) {
          debugPrint(
              '[OCR-V8] Phase 2.6: skip garbage suffix line $j: "$nextLine"');
          continue; // 不用 break，继续看下一行
        }
        if (suffixPart.isEmpty) continue;
        // ★ V8.1: 后缀行纯数字检测 — 防止份额数字混入（如 "136"）
        if (RegExp(r'^\d{3,}$').hasMatch(suffixPart)) continue;
        // ★ OCR 变体规范化: 台→合, 指教→指数, (QDI1→(QDII
        var normSuffix = suffixPart
            .replaceAll('台', '合')
            .replaceAll('指教', '指数')
            .replaceAll('(QDI1', '(QDII')
            .replaceAll(')-LOF)', '-LOF)');
        // ★ 重叠检测: 基名尾与后缀头有重叠字符时去重
        // 如 "科技" + "技指数" → 重叠 "技" → "科技指数"
        var baseName = d.name;
        for (int overlap = 1;
            overlap <= 3 &&
                overlap < normSuffix.length &&
                overlap < baseName.length;
            overlap++) {
          if (baseName.endsWith(normSuffix.substring(0, overlap))) {
            baseName = baseName.substring(0, baseName.length - overlap);
            debugPrint(
                '[OCR-V8] Phase 2.6: overlap detected, trimmed base to "$baseName"');
            break;
          }
        }
        final combinedName = baseName + normSuffix;
        final clean = _v8Clean(combinedName);
        debugPrint(
            '[OCR-V8] Phase 2.6 try: "${d.name}" + "$suffixPart" → "$clean" (line $j: "$nextLine")');
        if (_v8IsValidName(clean)) {
          final isDup = holdings.any((h) => _isDuplicateName(h.name, clean));
          if (!isDup) {
            holdings.add(RecognizedHolding(
              code: '',
              name: clean,
              amount: d.amount,
              yesterdayProfit: null,
              holdingProfit: null,
              holdingProfitRate: null,
              confidence: 0.5,
              needsCodeMatch: true,
            ));
            usedIndices.add(j);
            debugPrint(
                '[OCR-V8] Phase 2.6: completed "${d.name}" → "$clean" using line $j');
          } else {
            debugPrint('[OCR-V8] Phase 2.6: skip duplicate "$clean"');
          }
        }
        break; // 只看第一个含 typeWord 的行
      }
    }

    // ★ Phase 2.6 fallback: 对 Phase 2.6 未能补全的 deferred 项，仍以不完整名加入 holdings
    // 后端基金代码匹配可以补全名字（如"天弘中证细分化工" → 匹配到完整名）
    final completedNames = holdings.map((h) => h.name).toSet();
    for (final d in deferredHolding) {
      if (completedNames.contains(d.name)) continue; // 已被 Phase 2.6 补全
      if (holdings.any((h) => _isDuplicateName(h.name, d.name))) continue;
      if (!_fundCompanyNames.any((c) => d.name.contains(c)) &&
          !RegExp(r'[\u4e00-\u9fa5]{4,}').hasMatch(d.name)) {
        continue;
      }
      debugPrint(
          '[OCR-V8] Phase 2.6 fallback: adding incomplete "${d.name}" amt=${d.amount} with needsCodeMatch');
      holdings.add(RecognizedHolding(
        code: '',
        name: d.name,
        amount: d.amount,
        yesterdayProfit: null,
        holdingProfit: null,
        holdingProfitRate: null,
        confidence: 0.3,
        needsCodeMatch: true,
      ));
    }

    debugPrint('[OCR-V8] Total holdings found: ${holdings.length}');
    // ★ V8.2: 后处理 — 小写 c→C 归一化 + 后缀碎片合并
    for (int i = 0; i < holdings.length; i++) {
      final h = holdings[i];
      // 类型词后的小写 a/b/c → 大写
      var name = h.name.replaceAllMapped(
        RegExp(r'(混合|指数|指教|股票|债券|ETF|LOF|QDII|联接|增强|优选|混台)([abc])$'),
        (m) => '${m[1]}${m[2]!.toUpperCase()}',
      );
      holdings[i] = RecognizedHolding(
        code: h.code,
        name: name,
        amount: h.amount,
        yesterdayProfit: h.yesterdayProfit,
        holdingProfit: h.holdingProfit,
        holdingProfitRate: h.holdingProfitRate,
        confidence: h.confidence,
        needsCodeMatch: h.needsCodeMatch,
      );
    }
    // ★ V8.2: 后缀碎片合并 — 同金额的「不完整名 + 后缀碎片名」→ 合并
    // 如 "天弘中证I业有色"(amt=222.38) + "金属主题ETF联接C"(amt=222.38)
    //   → "天弘中证工业有色金属主题ETF联接C"
    final merged = <int>{}; // indices to remove
    for (int i = 0; i < holdings.length; i++) {
      if (merged.contains(i)) continue;
      final hi = holdings[i];
      for (int j = i + 1; j < holdings.length; j++) {
        if (merged.contains(j)) continue;
        final hj = holdings[j];
        // 同金额（允许微小误差）且名字可拼接
        if ((hi.amount - hj.amount).abs() < 0.1) {
          final nameI = hi.name;
          final nameJ = hj.name;
          // 检测哪个是前缀碎片、哪个是后缀碎片
          final suffixPattern = RegExp(
              r'^(金属|主题|产业|科技|先锋|制造|装备|新能源|低碳|有色|化工|光伏|电网|通信|细分|瑞享)(.*)(ETF|LOF|联接|混合|指数|股票|债券|增强|优选)(\\([^)]*\\))?[A-C]?$');
          String? mergedName;
          if (suffixPattern.hasMatch(nameJ) && !suffixPattern.hasMatch(nameI)) {
            // j 是后缀碎片，i 是前缀碎片
            mergedName = _v8Clean(nameI + nameJ);
          } else if (suffixPattern.hasMatch(nameI) &&
              !suffixPattern.hasMatch(nameJ)) {
            // i 是后缀碎片，j 是前缀碎片
            mergedName = _v8Clean(nameJ + nameI);
          }
          if (mergedName != null && _v8IsValidName(mergedName)) {
            debugPrint(
                '[OCR-V8] V8.2 merge: "$nameI" + "$nameJ" → "$mergedName"');
            holdings[i] = RecognizedHolding(
              code: hi.code,
              name: mergedName,
              amount: hi.amount,
              yesterdayProfit: hi.yesterdayProfit,
              holdingProfit: hi.holdingProfit,
              holdingProfitRate: hi.holdingProfitRate,
              confidence: 0.7,
              needsCodeMatch: true,
            );
            merged.add(j);
          }
        }
      }
    }
    if (merged.isNotEmpty) {
      final mergedList = <RecognizedHolding>[];
      for (int i = 0; i < holdings.length; i++) {
        if (!merged.contains(i)) mergedList.add(holdings[i]);
      }
      holdings.clear();
      holdings.addAll(mergedList);
    }
    // ★ V8.3: suffixFragments 合并 — 后缀碎片（无公司前缀）+ 前缀碎片（无类型后缀）→ 按金额匹配
    for (final sf in suffixFragments) {
      bool matched = false;
      for (int i = 0; i < holdings.length; i++) {
        final h = holdings[i];
        // 同金额 + 前缀碎片缺类型词
        if ((h.amount - sf.amount).abs() < 0.1) {
          final hasTypeSuffix = RegExp(
                  r'(混合|指数|股票|债券|ETF|LOF|QDII|联接|增强|优选|量化)(\\([^)]*\\))?[A-Ca-c]?$')
              .hasMatch(h.name);
          if (!hasTypeSuffix) {
            // h 是前缀碎片，sf 是后缀碎片 → 拼接
            final trialName = _v8Clean(h.name + sf.name);
            if (_v8IsValidName(trialName)) {
              debugPrint(
                  '[OCR-V8] V8.3 suffix merge: "${h.name}" + "${sf.name}" → "$trialName"');
              holdings[i] = RecognizedHolding(
                code: h.code,
                name: trialName,
                amount: h.amount,
                yesterdayProfit: h.yesterdayProfit,
                holdingProfit: h.holdingProfit,
                holdingProfitRate: h.holdingProfitRate,
                confidence: 0.7,
                needsCodeMatch: true,
              );
              matched = true;
              break;
            }
          }
        }
      }
      if (!matched) {
        // 后缀碎片没匹配到，单独加入（needsCodeMatch=true）
        debugPrint(
            '[OCR-V8] V8.3 suffix fragment unmatched: "${sf.name}" amt=${sf.amount}');
      }
    }
    for (int i = 0; i < holdings.length; i++) {
      debugPrint(
          '[OCR-V8]   #$i: ${holdings[i].name} amt=${holdings[i].amount}');
    }
    return holdings;
  }

  // V8: 清理基金名
  // ⚠️ 不 strip 尾部数字！因为基金名可能以字母+数字结尾
  static String _v8Clean(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'[\-+]\d{1,3}\.\d{2}'), ''); // 混入的昨日收益
    // 去除上一行涨跌幅末尾粘连的 % 及其残留（如 "+12.59%广发..." → 数字已被上一步清掉，剩 "%广发..."）
    s = s.replaceAll(RegExp(r'^[%\s]+'), '');
    s = s.replaceAll(RegExp(r'^[|!?;:，、\s]+'), ''); // | is OCR noise
    s = s.replaceAll(RegExp(r'[!?;:，、\s]+$'), '');
    // ❌ 已移除：s.replaceAll(RegExp(r'\d+$'), '') — 会错误清除基金名尾部数字
    s = s.replaceAll(',', ''); // Y坐标合并逗号噪声
    s = s.replaceAll(RegExp(r'\s+'), '');
    // ★ V8.2: 繁体→简体归一化（OCR常见误识）
    s = s
        .replaceAll('運', '运')
        .replaceAll('見', '见')
        .replaceAll('選', '选')
        .replaceAll('題', '题')
        .replaceAll('聯', '联')
        .replaceAll('產', '产')
        .replaceAll('業', '业')
        .replaceAll('備', '备')
        .replaceAll('裝', '装')
        .replaceAll('質', '质')
        .replaceAll('網', '网')
        .replaceAll('電', '电')
        .replaceAll('設', '设')
        .replaceAll('備', '备')
        .replaceAll('債', '债')
        .replaceAll('贏', '赢')
        .replaceAll('増', '增');

    // ★ V8.1: 去除日文乱码片段（ル、キ、國、龜、@ 等不应出现在基金名中）
    // 去掉 CJK 扩展区/日文假名/特殊符号
    s = s.replaceAll(
        RegExp(r'[\u3040-\u309F\u30A0-\u30FF\uFF65-\uFF9F@龜國]+'), '');

    // ★ V8.2: OCR 常见单字误识修正
    s = s.replaceAll('I业', '工业'); // 大写 I 被误识为 工
    s = s.replaceAll('高瑞', '高端'); // 瑞/端 形近
    s = s.replaceAll('同奉', '同泰'); // 奉/泰 形近
    s = s.replaceAll('运见', '远见'); // 运/远 形近（广发远见智选混合）
    s = s.replaceAll('在题', '主题'); // 在/主 形近
    s = s.replaceAll('FTF', 'ETF'); // F/E 形近
    s = s.replaceAll('综台', '综合'); // 台/合 形近
    s = s.replaceAll('瑞亨', '瑞享'); // 亨/享 形近
    s = s.replaceAll('利技', '科技'); // 利/科 形近
    s = s.replaceAllMapped(
      RegExp(r'标普生物料'),
      (m) => '标普生物科技',
    );
    // ★ 修复: 去掉末尾重复字母（如 "混合Cc" → "混合C"）
    s = s.replaceAll(RegExp(r'([A-Za-z])\1+$'), r'$1');
    // ★ 修复: OCR把类别后缀后的小写c误识为数字0（如 "混合0" → "混合C"）
    s = s.replaceAllMapped(
      RegExp(r'(混合|指数|指教|股票|债券|ETF|LOF|QDII|联接|增强|混台|优选)(\([^)]*\))?0$'),
      (m) => '${m[1]}${m[2] ?? ''}C',
    );
    // ★ V8.1: 去除拼接进来的纯数字/份额（如 "C136" → "C"，"(LOF)C136" → "(LOF)C"）
    // 匹配：类型后缀([A-C])后紧跟3位以上纯数字（这是份额，不是基金名部分）
    s = s.replaceAllMapped(
      RegExp(r'([A-C])[0-9]{3,}$'),
      (m) => m[1]!,
    );
    // ★ V8.1: QDII 编码容错（QDIl/QDILA/QDIL/QDIIA 等OCR误识 → QDII）
    // ⚠️ A/B 是份额类别后缀，不属于 QDII 误识，必须保留
    // ⚠️ 如果有开括号但无闭括号，补上闭括号
    s = s.replaceAllMapped(
      RegExp(r'QDI[LlI1]*(\)|）)?([A-C])?'),
      (m) {
        final hasOpenParen =
            m.start > 0 && RegExp(r'[\(（]').hasMatch(s[m.start - 1]);
        final closeParen = m[1] ?? (hasOpenParen ? ')' : '');
        final suffix = m[2] ?? '';
        return 'QDII$closeParen$suffix';
      },
    );
    // 去掉"指数教基金國"等拼接垃圾（连续3个以上非基金名词性的汉字组合）
    s = s.replaceAll(RegExp(r'(指数|指教)(教|基金)(國|区|园)?$'), '');
    return s.trim();
  }

  // V8: 验证基金名有效性
  // ★ V8.1: 增加乱码/拼接垃圾检测
  static bool _v8IsValidName(String name) {
    if (name.length < 4) return false;
    if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(name)) return false;
    if (!_fundCompanyNames.any((c) => name.contains(c))) return false;
    // 完整后缀关键词
    if (RegExp(r'^(混合|指数|股票|债券|ETF|LOF|QDII|联接)[A-C]?$').hasMatch(name)) {
      return false;
    }
    // 单字符纯类别后缀：混/指/股/债/联 + 可选字母/数字后缀
    if (RegExp(r'^[混合指数股票债券ETFLOFQDII联接]+[A-C0-9]?$').hasMatch(name)) {
      return false;
    }
    // ★ V8.1: 检测日文乱码 — 含假名字符的名称无效
    if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(name)) return false;
    // ★ V8.1: 检测拼接垃圾 — 含"指数教基金國"等非基金名词性组合
    if (RegExp(r'(指数|指教)教').hasMatch(name)) return false;
    // ★ V8.1: 资讯标题渗入 — 含"利好事件""投资锦囊"等
    if (_infoTitlePattern.hasMatch(name)) return false;
    // ★ V8.1: 份额数字混入 — 类型后缀后紧跟3位以上数字（如"C136"）
    if (RegExp(r'[A-C]\d{3,}').hasMatch(name)) return false;
    return true;
  }

  // ============================================================
  // 天天基金解析器
  // ============================================================

  static List<RecognizedHolding> _parseTiantian(List<String> lines) {
    final holdings = <RecognizedHolding>[];
    final usedIndices = <int>{};

    for (int i = 0; i < lines.length; i++) {
      if (usedIndices.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final codeMatch = RegExp(r'\b(\d{6})\b').firstMatch(line);
      if (codeMatch == null) continue;
      final code = codeMatch.group(1)!;
      if (!_isValidFundCode(code)) continue;

      double? amount = _extractAmountFromLine(line);
      String name = '';
      final nameMatch = RegExp(r'([\u4e00-\u9fa5][\u4e00-\u9fa5A-Za-z0-9]{2,})')
          .firstMatch(line);
      if (nameMatch != null) name = _cleanFundName(nameMatch.group(1)!);

      if (amount == null || amount < 1) {
        for (int j = i + 1; j < lines.length && j <= i + 3; j++) {
          final a = _extractAmountFromLine(lines[j].trim());
          if (a != null && a >= 1) {
            amount = a;
            usedIndices.add(j);
            break;
          }
        }
      }

      if (amount != null && amount >= 1) {
        holdings.add(RecognizedHolding(
          code: code,
          name: name,
          amount: amount,
          yesterdayProfit: null,
          holdingProfit: null,
          holdingProfitRate: null,
          confidence: 0.8,
          needsCodeMatch: name.isEmpty,
        ));
      }
    }

    if (holdings.isEmpty) return _parseGeneric(lines);

    return holdings;
  }

  // ============================================================
  // 通用兜底
  // ============================================================

  static List<RecognizedHolding> _parseGeneric(List<String> lines) {
    final holdings = <RecognizedHolding>[];
    for (final line in lines) {
      final holding = _parseSingleLine(line);
      if (holding != null && holding.amount > 0) holdings.add(holding);
    }
    if (holdings.isEmpty) {
      for (final line in lines) {
        final amount = _extractAmountFromLine(line);
        if (amount != null && amount >= 100) {
          final nameMatch = RegExp(r'([\u4e00-\u9fa5]{4,})').firstMatch(line);
          if (nameMatch != null) {
            final name = _cleanFundName(nameMatch.group(1)!);
            if (name.length >= 4) {
              holdings.add(RecognizedHolding(
                code: '',
                name: name,
                amount: amount,
                yesterdayProfit: null,
                holdingProfit: null,
                holdingProfitRate: null,
                confidence: 0.3,
                needsCodeMatch: true,
              ));
            }
          }
        }
      }
    }

    return holdings;
  }

  // ============================================================
  // 单行解析
  // ============================================================

  static RecognizedHolding? _parseSingleLine(String line) {
    if (line.isEmpty) return null;
    if (_isNoiseLine(line)) return null;
    if (_isHeaderLine(line)) return null;

    final amount = _extractAmountFromLine(line);
    if (amount == null || amount < 10) return null;

    final nameMatch = RegExp(r'([\u4e00-\u9fa5]{4,})').firstMatch(line);
    final name = nameMatch != null ? _cleanFundName(nameMatch.group(1)!) : '';
    if (name.length < 4) return null;

    String code = '';
    final codeMatch = RegExp(r'\b(\d{6})\b').firstMatch(line);
    if (codeMatch != null && _isValidFundCode(codeMatch.group(1)!)) {
      code = codeMatch.group(1)!;
    }

    return RecognizedHolding(
      code: code,
      name: name,
      amount: amount,
      confidence: code.isNotEmpty ? 0.8 : 0.4,
      needsCodeMatch: code.isEmpty,
    );
  }

  // ============================================================
  // 去重
  // ============================================================

  static List<RecognizedHolding> _deduplicateHoldings(
      List<RecognizedHolding> holdings) {
    final result = <RecognizedHolding>[];
    for (final h in holdings) {
      final isDup = result.any((r) => _isDuplicateName(r.name, h.name));
      if (!isDup) result.add(h);
    }
    return result;
  }

  // ============================================================
  // 辅助方法
  // ============================================================

  /// 归一化
  static String _normalizeOcrLine(String line) {
    var s = line.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll('，', ',').replaceAll('。', '.').replaceAll('：', ':');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// 昨日收益行
  /// ★ 修复: 有中文的行不是纯收益行（如"混合C14.40-3.80"）
  static bool _isPureProfitLine(String line) {
    final trimmed = line.trim();
    // 有中文的可能是基金名行，不是纯收益行
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(trimmed)) return false;
    return RegExp(r'^[+-]\d[\d,]*\.\d{2}$').hasMatch(trimmed);
  }

  /// 纯金额行（无符号数字）
  static bool _isPureAmountLine(String line) {
    return RegExp(r'^\d[\d,]*\.\d{2}$').hasMatch(line.trim());
  }

  /// 分类后缀行
  static bool _isClassSuffix(String line) {
    final l = line.trim();
    if (l.length > 15) {
      return false;
    }
    if (_isPureProfitLine(l) || _isPureAmountLine(l)) {
      return false;
    }
    if (_isNoiseLine(l)) {
      return false;
    }
    // 单字母
    if (RegExp(r'^[A-Za-z]$').hasMatch(l)) {
      return true;
    }
    // 短行含分类词
    if (l.length <= 8 &&
        RegExp(r'[合联接指数股票债券混合ETF]').hasMatch(l) &&
        RegExp(r'[A-Ca-c]').hasMatch(l)) {
      return true;
    }
    if (_fundSuffixKeywords.any((kw) => l.contains(kw)) && l.length <= 12) {
      return true;
    }
    return false;
  }

  /// 检测行中是否包含金额数字
  static bool _hasAmount(String line) {
    return RegExp(r'\d[\d,]*\.\d{2}').hasMatch(line);
  }

  /// 噪声行
  /// ★ 修复: 含金额的行不可能是噪声（噪声关键词是用来过滤纯文本碎片的）
  /// ★ V8.1: 增加资讯标题行过滤
  static bool _isNoiseLine(String line) {
    // 含金额的行一定是有效数据行，跳过噪声检测
    if (_hasAmount(line)) return false;

    for (final kw in _noiseKeywords) {
      if (line.contains(kw)) return true;
    }
    for (final kw in _fundMarketKeywords) {
      if (line.contains(kw)) return true;
    }
    // ★ V8.1: 资讯标题行过滤
    if (_infoTitlePattern.hasMatch(line)) return true;
    return false;
  }

  /// 后缀行检测 — 无公司名、有±数字、无%、短行、非噪声
  static bool _isSuffixLine(String line) {
    if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) return false;
    if (line.contains('%')) return false;
    if (_fundCompanyNames.any((c) => line.contains(c))) return false;
    if (line.length > 20) return false;
    if (!RegExp(r'[+-]\d[\d,]*\.?\d*').hasMatch(line)) return false;
    return true;
  }

  /// 头部导航行
  static bool _isHeaderLine(String line) {
    const navWords = ['全部', '偏股', '偏债', '名称', '排序'];
    if (navWords.contains(line)) return true;
    if (line.contains('持有收益率排序')) return true;
    if (line.contains('我的持有')) return true;
    if (line.contains('基金销售服务')) return true;
    return false;
  }

  /// 清理基金名（去噪声前缀、货币符号、空格）
  static String _cleanFundName(String name) {
    var s = name.trim();
    // 去掉开头OCR噪声字符（"！？"等）
    s = s.replaceAll(_nameNoisePrefix, '');
    // 去掉货币金额
    s = s.replaceAll(RegExp(r'[¥￥]\s*[\d,]+\.\d{2}'), '');
    // 去掉空格
    s = s.replaceAll(RegExp(r'\s+'), '');
    return s.trim();
  }

  /// 从行中提取金额 — 取行中所有数字里第一个 ≥10 的非纯收益/非%数字
  static double? _extractAmountFromLine(String line) {
    final trimmed = line.trim();
    // 纯收益行（无中文的开头±数字）→ 不取
    if (RegExp(r'^[+-]\d[\d,]*\.\d{2}$').hasMatch(trimmed)) return null;

    // ¥ 前缀 → 优先
    final yenMatch = RegExp(r'[¥￥]\s*([\d,]+\.\d{2})').firstMatch(line);
    if (yenMatch != null) return _parseAmount(yenMatch.group(1)!);

    // 千分位格式 (1,234.56) → 优先
    final commaMatch =
        RegExp(r'\b(\d{1,3}(?:,\d{3})+\.\d{2})\b').firstMatch(line);
    if (commaMatch != null) return _parseAmount(commaMatch.group(1)!);

    // 通用: 找到所有 XXXX.XX 模式，取第一个 ≥10 且不在%后的
    for (final m in RegExp(r'(\d[\d,]*\.\d{2})').allMatches(line)) {
      // 跳过%后面的数字（那是收益率，不是金额）
      final end = m.end;
      if (end < line.length && line[end] == '%') continue;
      // 跳过紧跟+-号的负向看（数字后紧跟的 -XXX.XX 是昨日收益）
      final start = m.start;
      if (start > 0) {
        final prev = line[start - 1];
        if (prev == '-' || prev == '+') {
          // 检查是否是 "字母-金额" 模式（如 C-129.33）→ 前面是字母则有效
          if (start < 2 || !RegExp(r'[A-Za-z]').hasMatch(line[start - 2])) {
            continue;
          }
        }
      }
      final parsed = _parseAmount(m.group(1)!);
      if (parsed >= 10) return parsed;
    }
    return null;
  }

  /// 解析金额
  static double _parseAmount(String s) {
    return double.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  /// 有效基金代码
  static bool _isValidFundCode(String code) {
    if (code.length != 6) return false;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;
    if (code.startsWith('20')) {
      final month = int.tryParse(code.substring(2, 4));
      if (month != null && month >= 1 && month <= 12) return false;
    }
    if (RegExp(r'^[012]\d[0-5]\d[0-5]\d$').hasMatch(code)) return false;
    return true;
  }

  /// 基金名重复判断 — 只按前6字前缀比较，不用 contains() 防误杀
  static bool _isDuplicateName(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final len = a.length < b.length ? a.length : b.length;
    final cmpLen = len > 6 ? 6 : len;
    return a.substring(0, cmpLen) == b.substring(0, cmpLen);
  }

  // ============================================================
  // V9: 横向分析法核心实现
  // ============================================================

  /// X聚类：检测列边界
  /// 支付宝持仓截图固定4列布局：基金名 | 金额 | 昨日收益 | 收益率%
  /// 返回按left排序的列列表，null表示检测失败
  static List<_V9Column>? _v9DetectColumns(
      List<OcrBlock> blocks, double imageWidth) {
    if (blocks.isEmpty) return null;

    // ===== 直方图法列检测 =====
    // 将X轴分成小bin，统计每个bin的block数量，找到空白间隔作为列分割线
    const binWidth = 20.0;
    final numBins = (imageWidth / binWidth).ceil() + 1;
    final histogram = List.filled(numBins, 0);
    for (final b in blocks) {
      final binIdx = (b.centerx / binWidth).floor();
      if (binIdx >= 0 && binIdx < numBins) histogram[binIdx]++;
    }

    // 找gap区域（低密度区间）
    final maxCount = histogram.reduce(math.max);
    final threshold = (maxCount * 0.1).floor(); // 低于10%峰值视为gap
    final gaps = <Map<String, double>>[];
    bool inGap = false;
    int gapStart = 0;

    for (int i = 0; i < numBins; i++) {
      if (histogram[i] <= threshold) {
        if (!inGap) {
          gapStart = i;
          inGap = true;
        }
      } else {
        if (inGap) {
          final gapMidX = ((gapStart + i) / 2) * binWidth;
          final gapWidth = (i - gapStart) * binWidth;
          gaps.add({'midX': gapMidX, 'width': gapWidth});
          inGap = false;
        }
      }
    }
    if (inGap) {
      final gapMidX = ((gapStart + numBins) / 2) * binWidth;
      final gapWidth = (numBins - gapStart) * binWidth;
      gaps.add({'midX': gapMidX, 'width': gapWidth});
    }

    // 取最宽的3个gap作为4列的分割线
    const targetCols = 4;
    gaps.sort((a, b) => (b['width']! - a['width']!).toInt());
    final selectedGaps = gaps.take(targetCols - 1).toList();
    selectedGaps.sort((a, b) => a['midX']!.compareTo(b['midX']!));
    final splitLines = selectedGaps.map((g) => g['midX']!).toList();

    debugPrint('[OCR-V9] Split lines: $splitLines');

    // 用分割线严格划分列
    final boundaries = <double>[0, ...splitLines, imageWidth];
    final columns = <_V9Column>[];
    for (int i = 0; i < boundaries.length - 1; i++) {
      final colLeft = boundaries[i];
      final colRight = boundaries[i + 1];
      // 收集属于此列的blocks（centerX在[left, right)范围内，最后一列含右边界）
      final members = blocks.where((b) {
        if (i == boundaries.length - 2) {
          return b.centerx >= colLeft && b.centerx <= colRight;
        }
        return b.centerx >= colLeft && b.centerx < colRight;
      }).toList();
      if (members.isEmpty) continue;
      final centroid = members.map((b) => b.centerx).reduce((a, b) => a + b) /
          members.length;
      columns.add(_V9Column(
        index: i,
        left: colLeft,
        right: colRight,
        centroid: centroid,
      ));
    }

    // 按left排序并重新编号
    columns.sort((a, b) => a.left.compareTo(b.left));
    for (int i = 0; i < columns.length; i++) {
      // 重新赋值index
    }

    debugPrint(
        '[OCR-V9] Columns: ${columns.map((c) => "Col${c.index}: ${c.left.toInt()}-${c.right.toInt()} centroid=${c.centroid.toInt()}").join(" | ")}');

    // 至少3列才有效
    if (columns.length < 3) return null;
    return columns;
  }

  /// Y聚类：检测逻辑行
  /// 使用层次聚类（单链接），阈值基于中位行高
  static List<_V9Row> _v9DetectRows(List<OcrBlock> blocks) {
    if (blocks.isEmpty) return [];

    // 计算所有block的高度
    final heights = blocks.map((b) => b.bottom - b.top).toList();
    heights.sort();
    final medianHeight =
        heights.isNotEmpty ? heights[heights.length ~/ 2] : 30.0;
    // 行间距阈值：中位行高的60%（比V8合并的40%更宽松）
    final rowThreshold = medianHeight * 0.6;

    // 按centerY排序
    final sorted = List<OcrBlock>.from(blocks);
    sorted.sort((a, b) => a.centery.compareTo(b.centery));

    // 层次聚类（单链接）：如果与最近行的centerY差值<=threshold则合并
    final rows = <_V9Row>[];
    _V9Row? currentRow;

    for (final block in sorted) {
      if (currentRow == null ||
          (block.centery - currentRow.centery).abs() > rowThreshold) {
        currentRow = _V9Row(blocks: [], centery: block.centery);
        rows.add(currentRow);
      }
      currentRow.blocks.add(block);
      // 更新行的centerY为平均（加权）
      currentRow.centery =
          currentRow.blocks.map((b) => b.centery).reduce((a, b) => a + b) /
              currentRow.blocks.length;
    }

    return rows;
  }

  /// 构建行×列矩阵
  /// 每个cell包含落入该行该列X范围内的所有block文本
  static List<List<String>> _v9BuildMatrix(
    List<OcrBlock> blocks,
    List<_V9Row> rows,
    List<_V9Column> columns,
  ) {
    final matrix = List.generate(
      rows.length,
      (_) => List.generate(columns.length, (_) => ''),
    );

    for (final block in blocks) {
      // 找到所属行
      int? rowIndex;
      for (int r = 0; r < rows.length; r++) {
        if (rows[r].blocks.contains(block)) {
          rowIndex = r;
          break;
        }
      }
      if (rowIndex == null) continue;

      // 找到所属列（block中心点落在哪列范围内）
      int? colIndex;
      for (int c = 0; c < columns.length; c++) {
        if (block.centerx >= columns[c].left &&
            block.centerx <= columns[c].right) {
          colIndex = c;
          break;
        }
      }
      if (colIndex == null) continue;

      // 追加文本到对应cell
      if (matrix[rowIndex][colIndex].isNotEmpty) {
        matrix[rowIndex][colIndex] += ' ${block.text}';
      } else {
        matrix[rowIndex][colIndex] = block.text;
      }
    }

    // 调试输出矩阵
    for (int r = 0; r < rows.length; r++) {
      debugPrint('[OCR-V9] Row$r: ${matrix[r].map((c) => '["$c"]').join(' ')}');
    }

    return matrix;
  }

  /// 检测噪声文本（广告、推广、UI元素等）
  static bool _v9IsNoiseText(String text) {
    const noiseKeywords = [
      '基金经理',
      '看好',
      '赛道',
      '稳健理财',
      '灵活申赎',
      '推荐',
      '热门',
      '新发',
      '理财',
      '申赎'
    ];
    for (final kw in noiseKeywords) {
      if (text.contains(kw)) return true;
    }
    // 纯数字+标点（总资产等）
    if (RegExp(r'^[\d,.+\-()\s%]+$').hasMatch(text)) return true;
    // 太长且无中文
    if (text.length > 20 && !RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) {
      return true;
    }
    return false;
  }

  /// 清理基金名中可能的噪声前缀
  static String _v9CleanFundName(String name) {
    const noiseKeywords = ['基金经理', '看好', '赛道', '稳健理财', '灵活申赎', '推荐', '热门'];
    for (final kw in noiseKeywords) {
      final idx = name.indexOf(kw);
      if (idx >= 0) {
        final after = name.substring(idx + kw.length);
        if (after.isNotEmpty && RegExp(r'[\u4e00-\u9fff]').hasMatch(after)) {
          name = after;
        } else {
          name = name.substring(0, idx);
        }
      }
    }
    // 去除前导数字/标点（如'12,649.05'混入）
    name = name.replaceFirst(RegExp(r'^[\d,.+\-()%\s]+'), '');
    return name.trim();
  }

  /// 从矩阵提取持仓记录
  /// 策略：逐行扫描，识别数据行（含金额+收益率），向上关联基金名
  /// 从 OCR 乱码率值中提取数值（处理 "占759%" → 7.59, "4,42/" → 4.42 等）
  static double? _extractRateValue(String text) {
    // 去掉 % 符号
    var t = text.replaceAll('%', '').trim();
    // 处理占XXX% → OCR把数字/%读成"占"
    if (t.startsWith('占')) {
      final after = t.substring(1);
      // "占.629" → OCR把"5"读成"占"，小数点还在，parse原值
      if (after.contains('.')) {
        final n = double.tryParse(after.replaceAll(',', ''));
        if (n != null) return n;
      }
      // "占759" → OCR把"7."读成"占"，数字挤一起，÷100恢复
      final n = double.tryParse(after.replaceAll(',', ''));
      if (n != null) return n / 100;
    }
    // 处理 4,42/ → 4.42 (/ = 数字中的逗号)
    if (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    // 统一逗号为点
    t = t.replaceAll(',', '.');
    return double.tryParse(t);
  }

  static List<RecognizedHolding> _v9ExtractHoldings(
    List<List<String>> matrix,
    List<_V9Row> rows,
    List<_V9Column> columns,
  ) {
    final holdings = <RecognizedHolding>[];
    final usedRows = <int>{};
    const nameCol = 0;

    // ===== 列语义识别 =====
    // 找 rate 列（含有 % 的列）
    int rateCol = -1;
    for (int c = columns.length - 1; c >= 0; c--) {
      final colText = <String>[];
      for (int r = 0; r < matrix.length; r++) {
        if (matrix[r][c].isNotEmpty) colText.add(matrix[r][c]);
      }
      if (RegExp(r'%').hasMatch(colText.join(' '))) {
        rateCol = c;
        break;
      }
    }

    if (rateCol < 0) {
      debugPrint('[OCR-V9] 未找到 rate 列，回退');
      return [];
    }

    // 区分 3 列布局 vs 4+ 列布局
    // 3 列：[name | amount+profit | rate（含holding_profit和rate）]
    // 4 列：[name | amount | profit | rate]
    final bool is3ColLayout = columns.length == 3;

    // 4+ 列时动态检测 amountCol
    int amountCol = -1;
    if (!is3ColLayout) {
      for (int c = rateCol - 1; c >= 1; c--) {
        final sample = <String>[];
        for (int r = 0; r < matrix.length; r++) {
          if (matrix[r][c].isNotEmpty) sample.add(matrix[r][c]);
        }
        final joined = sample.join(' ');
        final plainCount =
            RegExp(r'(?<![+-])\d[\d,]*\.\d{2}').allMatches(joined).length;
        final signedCount =
            RegExp(r'[+-]\d[\d,]*\.\d{2}').allMatches(joined).length;
        if (plainCount > signedCount) {
          amountCol = c;
          break;
        }
      }
      if (amountCol < 0) amountCol = 1; // fallback
    }

    debugPrint(
        '[OCR-V9] 布局: ${is3ColLayout ? "3列" : "${columns.length}列"}, rateCol=$rateCol, amountCol=$amountCol');

    // ===== 逐行扫描：找 rate 行（含有 % 的行）=====
    for (int r = 0; r < matrix.length; r++) {
      if (usedRows.contains(r)) continue;

      final rateCell = matrix[r][rateCol].trim();
      // rate 行必须包含 %（或 OCR 乱码如 /、占），纯数字不算
      if (!RegExp(r'[%/占]').hasMatch(rateCell)) continue;
      final rateValue = _extractRateValue(rateCell);
      if (rateValue == null) continue;

      // ===== 提取 amount =====
      double? amount;

      if (is3ColLayout) {
        // 3 列：amount 在 row-1（同一基金的上一行，rateCol-1 = amount+profit 混合列）
        final aboveRow = r - 1;
        if (aboveRow >= 0 && !usedRows.contains(aboveRow)) {
          final mixedCol =
              matrix[aboveRow][rateCol - 1].trim().replaceAll(',', '');
          // 混合列包含 amount（纯正数开头） + profit（±号开头）
          // 取第一个未带 ± 号的数字作为 amount
          final amtMatch = RegExp(r'^(\d+\.\d{2})').firstMatch(mixedCol);
          if (amtMatch != null) {
            amount = double.tryParse(amtMatch.group(1)!);
          }
        }
      } else {
        // 4+ 列：amount 在同一行
        if (amountCol >= 0 && amountCol < matrix[r].length) {
          final amtCell = matrix[r][amountCol].trim();
          final amtMatch = RegExp(r'(\d[\d,]*\.\d{2})').firstMatch(amtCell);
          if (amtMatch != null) {
            amount = double.tryParse(amtMatch.group(1)!.replaceAll(',', ''));
          }
        }
      }

      // 3 列 fallback：amount 可能未在 row-1 找到，尝试从 name 列合并字段提取
      if ((amount == null || amount < 1) && is3ColLayout && r > 0) {
        final aboveName = matrix[r - 1][nameCol].trim();
        final merged =
            RegExp(r'^(.+?)\s+(\d[\d,]+\.\d{2})$').firstMatch(aboveName);
        if (merged != null) {
          amount = double.tryParse(merged.group(2)!.replaceAll(',', ''));
        }
      }
      // 3 列：也尝试从 row-1 rateCol-1 提取
      if ((amount == null || amount < 1) && is3ColLayout && r > 0) {
        final mixedCol = matrix[r - 1][rateCol - 1].trim();
        final amtMatch = RegExp(r'(\d[\d,]+\.\d{2})')
            .firstMatch(mixedCol.replaceAll(',', ''));
        if (amtMatch != null) {
          amount = double.tryParse(amtMatch.group(1)!);
        }
      }
      if (amount == null || amount < 1) continue;

      // ===== 提取基金名（多行拼接）=====
      // 3 列：name_prefix 在 row-1，name_suffix 在 row r
      // 4 列：向上搜索 name 列
      String fundName = '';
      final nameParts = <String>[];

      if (is3ColLayout) {
        // row-1: name_prefix + amount
        final aboveRow = r - 1;
        if (aboveRow >= 0) {
          var aboveNameCell = matrix[aboveRow][nameCol].trim();
          // 检查是否 name+amount 合并
          if (aboveNameCell.isNotEmpty) {
            final merged = RegExp(r'^(.+?)\s+(\d[\d,]+\.\d{2})$')
                .firstMatch(aboveNameCell);
            if (merged != null) {
              aboveNameCell = merged.group(1)!;
            }
            if (!_v9IsNoiseText(aboveNameCell)) {
              nameParts.add(aboveNameCell);
            }
          }
        }
        // row r: name_suffix（在 rate 行同一行）
        var currentNameCell = matrix[r][nameCol].trim();
        if (currentNameCell.isNotEmpty) {
          // 去掉前缀符号（如 "台" → "台"，有时有 "|"）
          currentNameCell =
              currentNameCell.replaceFirst(RegExp(r'^\|'), '').trim();
          if (!_v9IsNoiseText(currentNameCell)) {
            nameParts.add(currentNameCell);
          }
        }
      } else {
        // 向上搜索（4列布局）
        for (int nr = r - 1; nr >= 0; nr--) {
          if (usedRows.contains(nr)) break;
          final nameCell = matrix[nr][nameCol].trim();
          if (nameCell.isEmpty) break;
          // 停止：遇到另一个 rate 行
          final nrRate = matrix[nr][rateCol].trim();
          if (RegExp(r'\d[\d,]*\.\d{2}%').hasMatch(nrRate)) break;
          if (_v9IsNoiseText(nameCell)) break;
          if (nameParts.length >= 4) break;
          nameParts.insert(0, nameCell);
        }
        // 当前行的 name 列
        final currentName = matrix[r][nameCol].trim();
        if (currentName.isNotEmpty && nameParts.isEmpty) {
          nameParts.add(currentName.replaceFirst(RegExp(r'^\|'), '').trim());
        }
      }

      fundName = nameParts.join('').replaceAll(RegExp(r'\s+'), '');
      fundName = _v9CleanFundName(fundName);
      fundName = _v8Clean(fundName);

      // 应用 OCR 字形纠错（如果调用方有）
      fundName = _applyOcrCorrections(fundName);

      if (!_v8IsValidName(fundName)) {
        if (_fundCompanyNames.any((c) => fundName.contains(c)) &&
            fundName.length >= 4) {
          debugPrint('[OCR-V9] 宽松通过: "$fundName"');
        } else {
          debugPrint('[OCR-V9] 无效名称跳过: "$fundName" (row $r)');
          continue;
        }
      }

      // 去重
      final isDup = holdings.any((h) => _isDuplicateName(h.name, fundName));
      if (isDup) {
        debugPrint('[OCR-V9] 去重跳过: "$fundName"');
        continue;
      }

      holdings.add(RecognizedHolding(
        code: '',
        name: fundName,
        amount: amount,
        yesterdayProfit: null,
        holdingProfit: null,
        holdingProfitRate: rateValue,
        confidence: 0.8,
        needsCodeMatch: true,
      ));
      debugPrint(
          '[OCR-V9] 提取: "$fundName" amt=$amount rate=${rateValue.toStringAsFixed(2)}%');

      // 标记已使用的行
      if (is3ColLayout && r > 0) usedRows.add(r - 1);
      usedRows.add(r);
    }

    debugPrint('[OCR-V9] 共提取 ${holdings.length} 条持仓');
    return holdings;
  }

  /// 应用 OCR 字形纠错（V9 名提取后的最后一道防线）
  static String _applyOcrCorrections(String name) {
    // 注：大部分常用纠错已在 _v8Clean 中处理
    // 此处仅保留 _v8Clean 未覆盖的 V9 特有错误
    const corrections = {
      '永嘉': '永赢',
      '生夏': '华夏',
      '指教': '指数',
      '混台': '混合',
    };
    for (final entry in corrections.entries) {
      if (name.contains(entry.key)) {
        name = name.replaceAll(entry.key, entry.value);
      }
    }
    // OCR 经常把 "C" 识别为 "0"：修复后缀 "混合0/联接0/股票0/指数0/选0" → "XXC"
    final suffixFix = RegExp(r'^(.*)(混合|联接|股票|指数|选)(\d)$');
    final fixMatch = suffixFix.firstMatch(name);
    if (fixMatch != null) {
      name = '${fixMatch.group(1)}${fixMatch.group(2)}C';
    }
    return name;
  }
}

/// V9列定义
class _V9Column {
  final int index;
  final double left;
  final double right;
  final double centroid;
  _V9Column({
    required this.index,
    required this.left,
    required this.right,
    required this.centroid,
  });
}

/// V9行定义
class _V9Row {
  final List<OcrBlock> blocks;
  double centery;
  _V9Row({required this.blocks, required this.centery});
}
