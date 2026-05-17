// OCR 文本解析服务 - V7（锚点行严格过滤 + 搜索上界 + 前行名拼接）
// 架构：以 %收益率行为锚点，向前搜索基金名+金额

class RecognizedHolding {
  final String code;
  final String name;
  final double amount;
  final double? shares;
  final double confidence;
  final bool needsCodeMatch;

  RecognizedHolding({
    required this.code,
    required this.name,
    required this.amount,
    this.shares,
    this.confidence = 0.5,
    this.needsCodeMatch = false,
  });

  RecognizedHolding copyWith({
    String? code, String? name, double? amount,
    double? shares, double? confidence, bool? needsCodeMatch,
  }) {
    return RecognizedHolding(
      code: code ?? this.code, name: name ?? this.name,
      amount: amount ?? this.amount, shares: shares ?? this.shares,
      confidence: confidence ?? this.confidence,
      needsCodeMatch: needsCodeMatch ?? this.needsCodeMatch,
    );
  }
}

enum ScreenshotFormat { alipay, tiantian, generic }

class OcrService {
  // ============================================================
  // 关键词列表
  // ============================================================

  // 噪声关键词 — ⚠️ 只放纯广告/文案碎片，不放任何基金后缀/类别词
  // 后缀词（合C/混合C/指数C等）是 OCR 真实输出，放这里会导致数据静默丢失
  static const List<String> _noiseKeywords = [
    '金选指数基金', '市场解读', '去买入', '更多产品', '基金经理说',
    '能源替代', '清洁能源', '油转电', '撤退还是加仓', '去看看',
    '基金销售服务', '化工集体涨停', '科创盈利确定性',
  ];

  // 锚点行过滤：包含这些关键词的 %行 视为噪声（广告/解读文案混入）
  static const List<String> _fundMarketKeywords = [
    '市场解读', '基金经理说', '地缘扰动', '算力', '能源替代', '油转电',
    '化工集体涨停', '科创盈利', '撤退还是加仓', '需求进一步', '涨停',
    '确定性强', '业绩披露', '基金销售服务', '更多产品',
  ];

  // ============================================================
  // 基金公司名关键词（用于%后文本定位）
  // 来源：2022中国公募基金公司品牌价值榜TOP100
  // ============================================================
  static const List<String> _fundCompanyNames = [
    // 2字开头（高频识别词）
    '天弘', '华夏', '广发', '南方', '博时', '银华', '大成', '兴业', '长城',
    '东方', '华商', '新华', '安信', '金鹰', '银河', '长盛', '国金', '中海',
    '东吴', '华宝', '华富', '中航', '永赢', '博道', '同泰', '恒越', '朱雀',
    '中庚', '湘财', '南华', '江信',
    // 3字及以上开头
    '易方达', '嘉实', '招商', '中欧', '工银', '华安', '鹏华', '汇添富', '富国',
    '建信', '国泰', '平安', '景顺长城', '万家', '国海富兰克林', '创金合信',
    '中加', '泓德', '国投瑞银', '浦银安盛', '上银', '中信保诚', '鹏扬',
    '农银汇理', '圆信永丰', '申万菱信', '融通', '浙商', '民生加银',
    '前海开源', '诺安', '华泰保兴', '宝盈', '长安', '中融', '长信',
    '华泰柏瑞', '上投摩根', '德邦', '国联安', '光大保德信', '海富通',
    '中信建投', '摩根士丹利华鑫', '汇安', '汇丰晋信', '太平', '泰达宏利',
    '英大', '兴银', '中邮创业', '诺德', '红土创新', '财通', '中金',
    '西部利得', '北信瑞丰', '嘉合', '格林', '睿远', '鑫元', '恒生前海',
    '金元顺安', '西藏东财',
    // 特殊：用户基金名中出现的公司名变体
    '东方阿尔法', '摩根',
  ];

  // 基金名开头OCR噪声字符（"！？"等）
  static final _nameNoisePrefix = RegExp(r'^[！？?;；:：\s]+');

  static const List<String> _fundSuffixKeywords = [
    'ETF', 'LOF', 'QDII', '联接', '混合', '债券', '股票', '指数',
    '发起式', '证券投资基金', '基金',
  ];

  // ============================================================
  // 主入口
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
    final hasFundCompany = RegExp(r'(天弘|易方达|招商|平安|华夏|广发|南方|嘉实|富国|博时|中欧|工银|华安|鹏华|汇添富|兴全|景顺长城|交银|建信|银华|中银|国泰|华宝|永赢|同泰|诺德|泓德|恒越|新华|东吴|西部利得|万家|华泰柏瑞|长城|金鹰|申万菱信|长信|融通|国投瑞银|光大保德信|民生加银|浦银安盛|摩根|上投摩根)').hasMatch(text);
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

  static List<RecognizedHolding> _parseAlipay(List<String> lines) {
    final holdings = <RecognizedHolding>[];
    final usedIndices = <int>{};

    // V8: 找所有锚点行（含%收益率）
    final anchorIndices = <int>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (RegExp(r'[+-]\d[\d,]*\.\d{2}%').hasMatch(line)) {
        anchorIndices.add(i);
      }
    }

    // ★ 新增: 降级锚点检测 — OCR截断导致%丢失的行（如 "C-1.44+" 或 "指数C-2.096"）
    // 匹配：±数字（含2-3位小数），不以%结尾，前面紧跟中文或)C
    final fallbackAnchorIndices = <int>[];
    for (int i = 0; i < lines.length; i++) {
      if (anchorIndices.contains(i)) continue;
      final line = lines[i].trim();
      // 匹配: 中文/)/]/C 后紧跟 ±数字.XX（2或3位小数）不以%结尾
      // 例如: "混合C-1.44+", "指数C-2.096" — OCR截断%符号
      // ★ 修复: 前缀长度<=5才视为锚点；长前缀（如"平安高端装备混合-129.33"）是数据行，不是锚点
      final m = RegExp(r'(?:[\u4e00-\u9fa5\))\]]|C)[+-]\d[\d,]*\.\d{2,3}(?!%)').firstMatch(line);
      if (m != null && line.substring(0, m.start).trim().length <= 5) {
        fallbackAnchorIndices.add(i);
      }
    }

    if (anchorIndices.isEmpty && fallbackAnchorIndices.isEmpty) return _parseGeneric(lines);

    // 合并锚点列表（降级锚点排在后面）
    final allAnchors = <int>[...anchorIndices, ...fallbackAnchorIndices];
    // 降级锚点去重
    allAnchors.sort();

    for (int idx = 0; idx < allAnchors.length; idx++) {
      final anchorIdx = allAnchors[idx];
      if (usedIndices.contains(anchorIdx)) continue;

      final anchorLine = lines[anchorIdx].trim();
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
        rateMatch = RegExp(r'([+-]\d[\d,]*\.\d{2})%').firstMatch(anchorLine);
        if (rateMatch == null) { usedIndices.add(anchorIdx); continue; }
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
      }

      // ★ V8-1.5: 噪声锚点处理
      // 如果锚点行 afterPercent 不含任何基金公司名，这是纯噪声锚点
      // 直接反向搜索属于此锚点的基金，跳过 V8-2/V8-3 的常规数据行搜索
      if (!isFallback && rateMatch != null) {
        final afterPercent = anchorLine.substring(rateMatch.end).trim();
        if (afterPercent.isNotEmpty && !_fundCompanyNames.any((c) => afterPercent.contains(c))) {
          // 纯噪声锚点：收集锚点前所有候选行（从远→近的顺序）
          final candidates = <String>[];
          final candIdxs = <int>[];
          for (int k = anchorIdx - 1; k > prevAnchor && k >= anchorIdx - 12; k--) {
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
            if (a != null && a >= 10) { noiseAmt = a; usedIndices.add(candIdxs[ci]); break; }
          }

          // 后缀：基金名行之后的所有 class suffix 行
          final noiseSuffixes = <String>[];
          if (fundCi >= 0 && noiseAmt >= 10) {
            for (int ci = fundCi + 1; ci < candidates.length; ci++) {
              if (_isClassSuffix(candidates[ci]) && !_isNoiseLine(candidates[ci])) {
                noiseSuffixes.add(candidates[ci]);
                usedIndices.add(candIdxs[ci]);
              }
            }
          }

          if (noiseFund.isNotEmpty && noiseAmt >= 10) {
            final clean = _v8Clean(noiseFund.replaceAll(RegExp(r'[\-+]\d{1,3}\.\d{2}'), '') + noiseSuffixes.join());
            if (_v8IsValidName(clean) && !holdings.any((h) => _isDuplicateName(h.name, clean))) {
              holdings.add(RecognizedHolding(code: '', name: clean, amount: noiseAmt, confidence: 0.5, needsCodeMatch: true));
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

      // V8-2b: 兜底搜索（数据行搜索失败时）
      // V8-2b-1: 先向后找基金名（锚点下方，如平安高端装备混合第二行数据）
      if (dataLineIdx == null) {
        for (int k = anchorIdx + 1; k < lines.length && k <= anchorIdx + 3; k++) {
          if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
          final line = lines[k].trim();
          if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
          if (_fundCompanyNames.any((c) => line.contains(c))) {
            nameFrom3Row = line;
            break;
          }
        }
        // V8-2b-1b: 也向前找基金名（锚点上方，正常情况）
        if (nameFrom3Row.isEmpty) {
          for (int k = anchorIdx - 1; k > prevAnchor && k >= anchorIdx - 9; k--) {
            if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
            final line = lines[k].trim();
            if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
            if (_fundCompanyNames.any((c) => line.contains(c))) {
              nameFrom3Row = line;
              // 尝试从同一行提取金额
              final amountMatch = RegExp(r'[-]?(\d[\d,]*\.\d{2})').firstMatch(line);
              if (amountMatch != null) {
                final parsed = _parseAmount(amountMatch.group(1)!).abs();
                if (parsed >= 10) {
                  amount = parsed;
                  dataLineIdx = k;
                }
              }
              break;
            }
          }
        }
        // V8-2b-2: 向前找金额或持有收益（用于估算）
        int? amountOnlyIdx;
        for (int k = anchorIdx - 1; k > prevAnchor && k >= anchorIdx - 9; k--) {
          if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
          if (k == dataLineIdx) continue; // 跳过已处理的基金名行
          final line = lines[k].trim();
          if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
          final m = RegExp(r'^([+-]?\d[\d,]*\.\d{2})([+-]\d[\d,]*\.\d{2})?$').firstMatch(line);
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
          final hpMatch = RegExp(r'([+-]?\d[\d,]*\.\d{2})').firstMatch(afterPercent);
          if (hpMatch != null) {
            amount = _parseAmount(hpMatch.group(1)!).abs();
          }
        }
        // V8-2b-4: 如果找到了基金名，且有金额或持有收益
        if (nameFrom3Row.isNotEmpty && amount >= 10) {
          String raw = nameFrom3Row + suffix;
          final cleanName = _v8Clean(raw);
          if (_v8IsValidName(cleanName)) {
            final isDup = holdings.any((h) => _isDuplicateName(h.name, cleanName));
            if (!isDup) {
              holdings.add(RecognizedHolding(
                code: '', name: cleanName, amount: amount,
                confidence: amount >= 100 ? 0.7 : 0.5, // 低金额降低置信度
                needsCodeMatch: true,
              ));
            }
            usedIndices.add(anchorIdx);
            if (amountOnlyIdx != null) usedIndices.add(amountOnlyIdx);
            continue; // 已处理，跳到下一个锚点
          }
        }
        // 纯金额行兜底也没找到，跳过此锚点
        usedIndices.add(anchorIdx);
        continue;
      }

      // V8-3: 3行格式兜底（fundPrefix为空）
      if (fundPrefix.isEmpty) {
        int? pureNumIdx;
        for (int k = anchorIdx - 1; k > prevAnchor && k >= anchorIdx - 9; k--) {
          if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
          final line = lines[k].trim();
          if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
          if (RegExp(r'^[\d.+-]+$').hasMatch(line)) { pureNumIdx = k; break; }
        }
        if (pureNumIdx != null) {
          bool found = false;
          for (int k = pureNumIdx - 1; k > prevAnchor && k >= pureNumIdx - 2; k--) {
            if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
            final line = lines[k].trim();
            if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
            if (_fundCompanyNames.any((c) => line.contains(c))) { nameFrom3Row = line; found = true; break; }
          }
          if (!found) {
            for (int k = pureNumIdx + 1; k < lines.length && k <= pureNumIdx + 2; k++) {
              if (usedIndices.contains(k) || anchorIndices.contains(k)) continue;
              final line = lines[k].trim();
              if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
              if (_fundCompanyNames.any((c) => line.contains(c))) { nameFrom3Row = line; break; }
            }
          }
        }
      }

      // V8-4: 组装基金名
      String raw = fundPrefix + suffix;
      if (!_v8IsValidName(_v8Clean(raw)) && nameFrom3Row.isNotEmpty) {
        raw = nameFrom3Row + suffix;
      }
      final cleanName = _v8Clean(raw);

      // V8-5: 验证
      if (!_v8IsValidName(cleanName)) { usedIndices.add(anchorIdx); continue; }
      if (amount < 10) { usedIndices.add(anchorIdx); continue; }

      // V8-6: 去重 & 添加
      final isDup = holdings.any((h) => _isDuplicateName(h.name, cleanName));
      if (!isDup) {
        holdings.add(RecognizedHolding(
          code: '', name: cleanName, amount: amount,
          confidence: 0.7, needsCodeMatch: true,
        ));
      }

      usedIndices.add(anchorIdx);
      usedIndices.add(dataLineIdx);
    }

    // ===== Phase 1.5: 锚点间遗漏基金恢复 =====
    // 处理位于两个锚点之间、无专属锚点的基金
    // 如 "嘉实新能源新材料" 夹在噪声锚点与有效锚点之间，其数据行被上一锚点占用
    for (int i = 0; i < lines.length; i++) {
      if (usedIndices.contains(i)) continue;
      final line = lines[i].trim();
      if (line.isEmpty || _isNoiseLine(line) || _isHeaderLine(line)) continue;
      if (!_fundCompanyNames.any((c) => line.contains(c))) continue;
      if (_isPureAmountLine(line) || _isPureProfitLine(line)) continue;

      double? amt;
      final suffixes = <String>[];
      for (int j = i + 1; j < lines.length && j <= i + 8; j++) {
        final nl = lines[j].trim();
        if (_isNoiseLine(nl) || _isHeaderLine(nl)) break;
        // 锚点行或另一基金名行 → 停止搜索
        if (RegExp(r'^[+-]\d[\d,]*\.\d{2}%').hasMatch(nl)) break;
        if (_fundCompanyNames.any((c) => nl.contains(c))) break;
        // 金额行
        if (amt == null) {
          final a = _extractAmountFromLine(nl);
          if (a != null && a >= 10) { amt = a; continue; }
        }
        // 后缀行
        if (_isClassSuffix(nl)) { suffixes.add(nl); continue; }
        // 纯数字收益行
        if (RegExp(r'^[+-]?\d[\d,]*\.\d{2}$').hasMatch(nl)) continue;
        // 找到金额后的非预期行 → 结束
        if (amt != null) break;
      }

      if (amt != null && amt >= 10) {
        final clean = _v8Clean(line.replaceAll(RegExp(r'[\-+]\d{1,3}\.\d{2}'), '') + suffixes.join());
        if (_v8IsValidName(clean) && !holdings.any((h) => _isDuplicateName(h.name, clean))) {
          holdings.add(RecognizedHolding(code: '', name: clean, amount: amt, confidence: 0.5, needsCodeMatch: true));
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
      if (!_isSuffixLine(nextLine)) continue;

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
        holdings.add(RecognizedHolding(
          code: '', name: cleanName, amount: amt,
          confidence: 0.5, needsCodeMatch: true,
        ));
        usedIndices.add(i);
        usedIndices.add(i + 1);
      }
    }

    return holdings;
  }

  // V8: 清理基金名
  // ⚠️ 不 strip 尾部数字！因为基金名可能以字母+数字结尾
  static String _v8Clean(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'^[!?;:，、\s]+'), '');
    s = s.replaceAll(RegExp(r'[!?;:，、\s]+$'), '');
    s = s.replaceAll(RegExp(r'[\-+]\d{1,3}\.\d{2}'), ''); // 混入的昨日收益
    // ❌ 已移除：s.replaceAll(RegExp(r'\d+$'), '') — 会错误清除基金名尾部数字
    s = s.replaceAll(',', ''); // Y坐标合并逗号噪声
    s = s.replaceAll(RegExp(r'\s+'), '');
    // ★ 修复: 去掉末尾重复字母（如 "混合Cc" → "混合C"）
    s = s.replaceAll(RegExp(r'([A-Za-z])\1+$'), r'$1');
    return s.trim();
  }

  // V8: 验证基金名有效性
  // 允许单字符类别后缀：混/指/股/债/联 + 可选字母后缀（如混C、指A）
  static bool _v8IsValidName(String name) {
    if (name.length < 4) return false;
    if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(name)) return false;
    if (!_fundCompanyNames.any((c) => name.contains(c))) return false;
    // 完整后缀关键词
    if (RegExp(r'^(混合|指数|股票|债券|ETF|LOF|QDII|联接)[A-C]?$').hasMatch(name)) return false;
    // 单字符纯类别后缀：混/指/股/债/联 + 可选字母/数字后缀
    if (RegExp(r'^[混合指数股票债券ETFLOFQDII联接]+[A-C0-9]?$').hasMatch(name)) return false;
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
      final nameMatch =
          RegExp(r'([\u4e00-\u9fa5][\u4e00-\u9fa5A-Za-z0-9]{2,})').firstMatch(line);
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
          code: code, name: name, amount: amount,
          confidence: 0.8, needsCodeMatch: name.isEmpty,
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
                code: '', name: name, amount: amount,
                confidence: 0.3, needsCodeMatch: true,
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
      code: code, name: name, amount: amount,
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
  static bool _isNoiseLine(String line) {
    // 含金额的行一定是有效数据行，跳过噪声检测
    if (_hasAmount(line)) return false;
    
    for (final kw in _noiseKeywords) {
      if (line.contains(kw)) return true;
    }
    for (final kw in _fundMarketKeywords) {
      if (line.contains(kw)) return true;
    }
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
    final commaMatch = RegExp(r'\b(\d{1,3}(?:,\d{3})+\.\d{2})\b').firstMatch(line);
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
          if (start < 2 || !RegExp(r'[A-Za-z]').hasMatch(line[start - 2])) continue;
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
}
