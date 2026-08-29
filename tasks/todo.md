# CornerPet MVP Task Checklist

## Current Progress (2026-08-29)

- [x] Task 1–4：原生工程、L 形触发、400 ms 停留与 360×450 面板原型
- [x] Task 5：SwiftData 正式事项与唯一草稿持久化
- [x] Task 6：输入、条件提交、草稿恢复与精确错误重试
- [x] Task 7：输入优先面板、最新优先收件箱与双语占位导航
- [x] Task 8：五秒撤销、收藏与搜索、共享行内编辑、确认永久删除
- [x] Task 9：八状态面板生命周期、唯一 120 ms 收回、置顶移动缩放与尺寸持久化
- [x] Task 10–12：多显示器、设置、登录启动、每日提醒与小猫
- [ ] Task 12.5：UI 自动化、SwiftData 迁移与发布工程加固（进行中）
- [ ] Task 13–14：双语无障碍、隐私安全指标、扩展 QA 与候选版验证

Task 12 合并前最新自动验收：`CornerPetTests` 341/341、`CornerPetUITests` 21/21 通过，`git diff --check` 通过。首次 `xcodebuild` 因系统指向 Command Line Tools 而失败；仅为测试进程选择 Xcode Beta 后通过，归类为环境失败。成功 UI 运行时输入源为 `com.apple.keylayout.ABC`，中文候选窗干扰仍由 Task 12.5 建立可恢复的前置防护。

## Task 1: Project Baseline
**Outcome:** macOS 14、arm64 App 和两类测试目标可构建，隐藏启动。
**Acceptance:** Debug/Release 为 14.0 + arm64；accessory 模式；测试可运行。
**Verification:** xcodebuild clean test 与 Release build。
**Dependencies:** None · **Scope:** M

## Task 2: L-shaped Geometry
**Outcome:** 基本演示使用主屏左上角 86×20 + 20×86 pt 不可见 L 触发带。
**Acceptance:** 两臂贴屏幕边缘、20×20 交叠、边界正确；外侧 0.1 pt 不命中。
**Verification:** HotCornerGeometryTests。
**Dependencies:** Task 1 · **Scope:** S

## Task 3: Dwell and Mouse Adapter
**Outcome:** 400 ms 停留、100 ms 收回防抖、反转请求和 tracking-panel 边界适配。
**Acceptance:** 固定 400 ms 仅触发一次；两臂间移动不重置；不请求 Input Monitoring；不用 mouseMoved monitor。
**Verification:** HotCornerStateMachineTests、CornerTriggerCoordinatorTests、TriggerZonePanelTests + 前后台鼠标手测。
**Dependencies:** Task 2 · **Scope:** M

## Task 4: Full-screen Panel Prototype
**Outcome:** 360×450 pt 面板紧贴左边与菜单栏下沿，在全屏/Spaces 上方从角落生长并恢复焦点。
**Acceptance:** 260/180 ms 可反转；不退全屏或切 Space；无透明点击层。
**Verification:** Panel tests + Checkpoint A。
**Dependencies:** Task 3 · **Scope:** M

## Task 5: Item and Draft Persistence
**Outcome:** SwiftData 保存 IdeaItem 与唯一 Draft，重启恢复。
**Acceptance:** 草稿独立；空草稿不建事项；重复允许；成功提交才清空。
**Verification:** DraftStoreTests、ItemStoreTests、重启手测。
**Dependencies:** Task 4 · **Scope:** M

## Task 6: Conditional Submission
**Outcome:** 自动聚焦；Return 保存；按鼠标与置顶状态保持或收回。
**Acceptance:** Shift-Return 换行；Escape 保留草稿；失败保留文字并可重试。
**Verification:** CaptureViewModelTests + integration tests。
**Dependencies:** Task 5 · **Scope:** M

## Task 7: Capture-first Inbox
**Outcome:** 顶部输入、独立滚动收件箱、底部导航形成默认布局。
**Acceptance:** 输入五行后滚动；新事项置顶；固定区域不随列表滚动。
**Verification:** Inbox tests + CaptureFlowUITests。
**Dependencies:** Task 6 · **Scope:** M

## Task 8: Item Lifecycle
**Outcome:** 归档、五秒撤销、收藏、搜索、行内编辑、永久删除。
**Acceptance:** 勾选可撤销；取消收藏回收件箱；编辑和删除符合规格。
**Verification:** transition tests + LibraryFlowUITests。
**Dependencies:** Task 7 · **Scope:** M

## Task 9: Panel Lifecycle and Pinning
**Outcome:** 状态机管理空闲、草稿、编辑、错误、置顶、开关。
**Acceptance:** 空面板离开 120 ms 收回；草稿/编辑仅离开不收；置顶可移动缩放并归位。
**Verification:** PanelStateMachineTests + Pinning 手测。
**Dependencies:** Tasks 4, 6 · **Scope:** M

## Task 10: Corners and Displays
**Outcome:** 四角、主屏/所有屏、动态变化与置顶屏断开恢复。
**Acceptance:** 共享角落与数据；单面板；屏幕变化无陈旧热区。
**Verification:** ScreenCoordinatorTests + 多屏矩阵。
**Dependencies:** Tasks 2, 4, 9 · **Scope:** M

## Task 11: Settings and Login Launch
**Outcome:** 停留、角落、屏幕、语言、提醒、开机启动设置持久化。
**Acceptance:** 重启保留；SMAppService 与 UI 一致；冲突仅公开引导。
**Verification:** AppSettingsTests + 登录/注销手测。
**Dependencies:** Tasks 3, 10 · **Scope:** M

## Task 12: Reminder and Cat
**Outcome:** 每日提醒、十分钟稍后、休眠补发、代码绘制小猫。
**Acceptance:** 每日最多一次；休眠只补一次；可稍后或关闭。
**Verification:** ReminderPolicyTests + sleep/wake 手测。
**Dependencies:** Tasks 5, 11 · **Scope:** M

**Status:** 已通过 PR #1 合并到 `main`（`9ede8d7`）；自动单元与 UI 回归通过，sleep/wake 真实会话仍保留为手测证据。

## Task 12.5: Engineering Hardening
**Outcome:** UI 自动化输入源可恢复、SwiftData V1 可迁移、版本/Release/Hardened Runtime 与签名公证流程可执行。
**Acceptance:** 环境失败与产品回归可区分；Task 12 旧数据无损打开并重启恢复；unsigned Release 与全部自动化通过；缺失 Developer ID/公证凭据时明确失败而不伪造成功。
**Verification:** 脚本测试 + legacy-store migration tests + full unit/UI + Release build + static review。
**Dependencies:** Task 12 · **Scope:** M · **Status:** 进行中

## Task 13: Localization and Accessibility
**Outcome:** 中英文、VoiceOver、Reduce Motion 和错误文案完整。
**Acceptance:** 无 raw key/截断；控件有 identifier；Reduce Motion 120 ms 无过冲。
**Verification:** LocalizationUITests + accessibility audit。
**Dependencies:** Tasks 7–12 · **Scope:** M

## Task 14: Metrics, QA, and Release
**Outcome:** 无内容指标、自动化、兼容矩阵和 arm64 Release 形成证据。
**Acceptance:** 指标不接收文本；测试矩阵通过；Release BUILD SUCCEEDED。
**Verification:** clean test、Release build、七天验证表。
**Dependencies:** Tasks 1–13 · **Scope:** M

## 2026-08-26 Trigger Rewrite Slice

- [x] 纯状态机用 deadline generation 拒绝陈旧回调。
- [x] 新增两个透明、置顶、nonactivating tracking panels。
- [x] 注入 clock、pointer provider、deadline scheduler；deadline 时复核指针。
- [x] trigger + capture panel 组成 keep-open；离开全部区域 100 ms 后关闭，重入取消。
- [x] Escape 关闭；支持主屏全屏辅助 Space 演示。
- [x] 删除权限 coordinator、`MouseMonitor`、权限测试和 PBX 引用。
- [x] 直接 XCTest unit suite 57/57、Debug build、禁用 API 扫描。
- [ ] full scheme `xcodebuild test`（测试宿主卡在 worker materialization）以及 Apple 菜单、主屏触发、Escape、全屏手测。

详细来源：`docs/superpowers/specs/2026-08-26-atoll-style-corner-trigger-design.md` 与 `docs/superpowers/plans/2026-08-26-atoll-style-corner-trigger.md`。
