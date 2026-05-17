# 基金宝 - Fund App

> 基金管理应用 - Flutter 重构版

一款功能完整的基金管理 App，支持持仓追踪、实时估值、板块行情、资讯快讯、OCR 导入等核心功能。

## ✨ 功能特性

### 📊 持仓管理
- 持仓列表：实时估值 + 净值涨跌双维度展示
- 智能标签：交易时段自动切换「今日估算 / 昨日净值」
- 静默刷新：60 秒自动刷新，数据无变化不闪烁
- 收益汇总：当日收益、持仓成本一目了然

### 📈 行情中心
- 大盘指数：沪深300、上证50、创业板指、中证500 实时行情
- 板块排行：行业板块涨跌幅排名，成分股详情
- 基金排行：按类型筛选，支持多维度排序
- 关联基金：板块详情页展示相关基金及涨跌

### 🔍 基金搜索
- 模糊搜索：代码 / 名称 / 拼音快速查找
- 热门推荐：默认展示热门基金

### 📰 资讯快讯
- 东方财富实时财经新闻
- 按时间倒序展示

### 📸 OCR 导入
- 支付宝持仓截图一键识别（PaddleOCR）
- 自动解析基金代码、名称、持仓份额

### 📋 基金详情
- 净值走势图（1月/3月/6月/1年）
- 阶段涨幅（近1月/3月/6月/1年）
- 重仓持股 & 基金经理信息
- 交易记录（买入/卖出/分红）

## 🏗️ 技术架构

`
lib/
├── core/           # 主题、路由、依赖注入、异常定义
├── data/           # 数据层
│   ├── datasources/  # 远程 API + 本地存储
│   └── repositories/ # Repository 实现
├── domain/         # 领域层
│   ├── entities/     # 数据实体
│   ├── repositories/ # Repository 抽象
│   └── usecases/     # 用例
├── presentation/   # 表现层
│   ├── bloc/         # BLoC 状态管理（16个）
│   └── pages/        # 页面（17个）
└── utils/          # 工具类
`

### 核心技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.41.6 |
| 状态管理 | flutter_bloc ^8.1.3 |
| 网络请求 | dio ^5.4.0 |
| 路由 | go_router ^13.0.1 |
| 依赖注入 | get_it ^7.6.4 |
| OCR | paddle_ocr_flutter ^0.0.3 |
| 编码 | gbk_codec ^0.4.0 |

### 数据源

| API | 用途 | 编码 |
|-----|------|------|
| fundgz.1234567.com.cn | 实时估值（GZ） | GBK |
| fund.eastmoney.com/pingzhongdata | 基金详情（PZ） | UTF-8 |
| push2.eastmoney.com | 板块行情/成分股 | GBK |
| qt.gtimg.cn | 腾讯行情（大盘指数） | GBK |
| fundsuggest.eastmoney.com | 基金搜索 | UTF-8 |
| danjuanfunds.com | 蛋卷降级数据源 | UTF-8 |

### 三级降级策略

基金详情数据获取采用降级方案，确保数据可用性：

1. **Level 1**：GZ（估值）+ PZ（详情）并行 → 最完整
2. **Level 2**：GZ 失败（如 QDII 404）→ 仅 PZ → 有净值无估值
3. **Level 3**：PZ 也失败 → 蛋卷 API → 基础数据

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.41.6
- Dart >= 3.0
- Android Studio / VS Code
- 模拟器或真机（Android）

### 安装运行

`ash
# 克隆仓库
git clone https://github.com/a248418681/-fund-app.git
cd -fund-app

# 安装依赖
flutter pub get

# 运行
flutter run
`

### 构建 APK

`ash
flutter build apk --release
`

## 📁 页面一览

| 页面 | 路径 | 说明 |
|------|------|------|
| 持仓 | /holdings | 持仓列表 + 收益汇总 |
| 自选 | / | 自选基金 + 大盘指数 |
| 行情 | /market | 板块排行 + 基金排行 |
| 资讯 | /news | 财经新闻 |
| 搜索 | /search | 基金搜索 |
| 详情 | /detail/:code | 净值走势 + 重仓股 |
| 交易记录 | /trade | 买入/卖出/分红 |
| 板块详情 | /sector/:code | 成分股 + 关联基金 |
| 设置 | /settings | 应用设置 |

## 📝 License

MIT
