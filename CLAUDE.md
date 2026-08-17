# CLAUDE.md — AppUpdateKit

本仓库是全线 Apple App 的更新检查正身。范围裁决与不变式记录在此；README 是使用文档。

## 不变式（改动前先读）

1. **零配置是产品决策，不是省事。** 查询用 bundle identifier（不是 App Store ID）、
   版本读 bundle、storefront 读设备 locale + US fallback。⛔ 不给宿主加配置参数——
   每多一个参数就是每个项目多一个写错的机会（历史上 MONO 的 AppUpdateViewModel
   注释里留着 Filmo 的 bundle id、appStoreId 硬编码过错值）。
2. **策略常量写死在 kit 内**（1h 节流 / 24h 稍后提醒 / 跳过版本永久）。这是组合级
   裁决，⛔ 不接受逐 App 调阈值的 PR；要改就全线一起改。
3. **UserDefaults key 是迁移契约**：`IgnoredAppVersion`、`NextUpdateRemindDate`
   是 MONO / CodeCat / Filmo 上线版本已写入用户设备的 key，⛔ 永不改名。
   契约测试：`persistenceUsesTheLegacyKeyNames`。
4. **版本比较一律走 `AppVersion`**（数字逐段比较）。⛔ 禁止 `String.compare(options: .numeric)`
   或字典序比较进入本仓库。
5. **更新检查是启动期旁路能力**：任何失败只记日志，不 throw、不弹残缺 UI、
   不阻塞启动。`hasCompletedCheckThisLaunch` 在所有出口都必须置位（含失败与节流），
   好让宿主挡住「lookup 还没结束时更低优先级 surface 抢跑」。
   ⛔ 它不是「任何启动弹层都先等 lookup」的许可证——本地已就绪的候选必须先走仲裁。
6. **kit 不做展示仲裁**：只发布 `availableUpdate` 状态；由宿主的
   SheetCoordinator / SurfaceCoordinatorKit 决定何时展示。
7. **强制更新 / 最低版本闸门有意不做**（本产品线无此需求；要做也是独立能力，
   不挂在提醒式更新检查上）。

## CI 契约

`product-playbook` 的 `app-update-check-lint`（v6 起）以以下证据判定接入：

- canonical 依赖 `https://github.com/Jewel591/AppUpdateKit` + 自动兼容版本范围（`from:`）
- application target 生产源码 `import AppUpdateKit`
- 模块限定构造 `AppUpdateKit.AppUpdateController(...)`
- 生产调用 `checkForAppUpdate(...)`

改公开 API 名（`AppUpdateController` / `checkForAppUpdate`）必须同步改 lint，否则全线红灯。

## 本地化

catalog 在 `Sources/AppUpdateKit/Resources/Localizable.xcstrings`，英文字面量 key 为源文，
必译语言 de / es / fr / ja / ko / pt-BR / zh-Hans / zh-Hant（`l10n-manifest.json` 为 CI 真相源）。
译文由 agent 逐条定稿，⛔ 不走机翻。
