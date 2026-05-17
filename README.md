# 🏦 FundRadar — 基金实时估值与持仓分析工具

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20Architecture-brightgreen)]()
[![State Management](https://img.shields.io/badge/State-BLoC-00B4D8)]()

基于 Flutter 构建的跨平台基金实时估值工具，支持**盘中净值估算、持仓穿透分析、历史走势回溯**和**智能组合监控**。

## ✨ 核心功能

| 功能 | 描述 |
|------|------|
| 📊 **实时净值估算** | 基于基金持仓穿透与底层资产行情，实时估算基金盘中净值 |
| 📦 **持仓穿透分析** | 穿透基金重仓股/债券持仓，追踪标的实时涨跌 |
| 📈 **净值历史回测** | 多维度历史净值走势可视化，支持对比分析 |
| 🔔 **异动监控** | 持仓标的实时异动提醒，关键点位自动提示 |
| 📰 **基金资讯** | 聚合基金公告、研报、市场快讯 |
| 🌗 **深色模式** | 全组件深色/浅色自适应，交易时段低光友好 |

## 🏗️ 技术架构

`
lib/
├── core/           # 基础设施层
│   ├── constants/    # 全局常量
│   ├── di/          # 依赖注入 (Dependency Injection)
│   ├── exceptions/  # 异常体系
│   ├── router/      # 路由管理
│   └── theme/       # 主题系统
├── data/           # 数据层
│   ├── datasources/
│   │   ├── remote/    # 远程API数据源 (Dio HTTP Client)
│   │   └── local/     # 本地持久化
│   ├── models/       # 数据模型 (estimate/fund/holding/nav/news/portfolio)
│   └── repositories/ # 仓储实现
├── domain/         # 领域层（纯Dart, 零依赖）
│   ├── entities/     # 核心实体 (fund_entity — 16.8KB)
│   ├── repositories/ # 仓储接口
│   └── usecases/fund/ # 基金业务用例
├── presentation/   # 展示层
│   ├── bloc/         # BLoC 状态管理
│   ├── pages/        # 页面组件
│   └── widgets/      # 通用组件
└── utils/          # 工具函数
`

**设计模式**：Clean Architecture (核心/数据/领域/展示四层分离)
**状态管理**：BLoC (Business Logic Component)
**依赖注入**：自定义DI容器
**HTTP Client**：Dio + 自定义拦截器链

## 🚀 快速开始

`ash
# 安装依赖
flutter pub get

# 运行 (Debug)
flutter run

# 构建 APK
flutter build apk --release
`

## 📋 数据能力

- **实时估值**：基于基金持仓数据 + 底层标的实时行情，算法测算盘中净值
- **持仓穿透**：支持股票型/混合型/指数型基金的仓位穿透查询
- **历史回溯**：多时间维度净值曲线与回撤分析
- **多数据源聚合**：远程API + 本地缓存分层架构，确保弱网下核心数据可用

## 🛠️ 技术栈

| 层 | 技术 |
|---|------|
| 框架 | Flutter 3.x |
| 语言 | Dart |
| 架构 | Clean Architecture (Core/Data/Domain/Presentation) |
| 状态管理 | BLoC |
| HTTP | Dio |
| 路由 | GoRouter |

## 📱 平台支持

- ✅ Android
- 🚧 iOS (架构已预留)
- 🚧 Web (架构已预留)

---

*本项目为个人投资决策辅助工具，数据仅供参考，不构成投资建议。*