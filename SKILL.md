---
name: app-update-kit
description: 在任何 Apple App 里实现、迁移或排查「检查 App Store 新版本 / 更新提醒弹窗」能力时必须先加载：一律接 AppUpdateKit（Jewel591/AppUpdateKit），⛔ 不再手写 AppUpdateViewModel / iTunes Lookup 调用 / 版本比较。覆盖标准接入姿势、CI lint（app-update-check-lint v6）的四项装配证据、迁移时的删除清单与 UserDefaults key 兼容事实。本 skill 是接入索引，范围裁决正文在本仓库 CLAUDE.md。
---

# AppUpdateKit 接入 skill

（本文件是 skill 正身；各机器 `~/.agents/skills/app-update-kit/` 只放指向这里的壳。）

全线 Apple App 的更新检查唯一正身是 **[Jewel591/AppUpdateKit](https://github.com/Jewel591/AppUpdateKit)**
（本地 checkout：`~/Documents/DevProjects/Swift Projects/AppUpdateKit`）。
范围裁决与不变式读 kit 仓库 `CLAUDE.md`，用法读 `README.md`——本文件不复制正文。

## 何时触发

- 新项目要加「有新版本提醒」能力
- 存量项目里看到自研 `AppUpdateViewModel` / `AppStoreUpdateClient` / iTunes Lookup 手写调用
- `app-update-check-lint` 红灯
- 排查更新弹窗不出现 / 重复出现 / 版本比较错误

## 硬性规则

1. ⛔ 不手写更新检查。lookup、版本比较、提醒策略、标准 UI 全在 kit 内。
2. 接入 = 四项 lint 证据缺一不可（`app-update-check-lint` v6，validation 起硬闸）：
   - canonical URL + `Up to Next Major Version`（`from:`）依赖声明
   - application target 生产源码 `import AppUpdateKit`
   - **模块限定**构造 `AppUpdateKit.AppUpdateController()`（不带模块名不算证据）
   - 生产启动/恢复入口调用 `checkForAppUpdate(...)`（测试 / Preview / DEBUG 不算）
3. 迁移存量项目时**删除**自研实现（ViewModel、client、alert view、老单测），
   ⛔ 不保留两套并行检查。用户已有的「跳过此版本 / 稍后提醒」选择自动保留——
   kit 写死了旧 key（`IgnoredAppVersion` / `NextUpdateRemindDate`），零迁移代码。
4. 更新弹窗是 App 发起的 surface：经宿主 SheetCoordinator / SurfaceCoordinatorKit
   仲裁展示 `availableUpdate`；启动弹层链用 `hasCompletedCheckThisLaunch` 防竞态。
5. 设置页「检查更新」按钮用 `checkForAppUpdate(force: true)`（绕过节流与抑制）。
6. 零配置是不变式：⛔ 不给 kit 加 App Store ID / storefront / 阈值参数；
   要改策略就在 kit 内全线一起改（见 kit CLAUDE.md 不变式 1–2）。
