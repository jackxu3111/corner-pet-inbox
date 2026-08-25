# CornerPet MVP Task Checklist

## Task 1: Project Baseline
**Outcome:** macOS 14、arm64 App 和两类测试目标可构建，隐藏启动。
**Acceptance:** Debug/Release 为 14.0 + arm64；accessory 模式；测试可运行。
**Verification:** xcodebuild clean test 与 Release build。
**Dependencies:** None · **Scope:** M

## Task 2: L-shaped Geometry
**Outcome:** 四角由两个 43×6 pt 矩形组成不可见 L 热区。
**Acceptance:** 四角镜像、交叠、边界正确；外侧 0.1 pt 不命中。
**Verification:** HotCornerGeometryTests。
**Dependencies:** Task 1 · **Scope:** S

## Task 3: Dwell and Mouse Adapter
**Outcome:** 三档停留、离开取消、80 ms 防抖、反转请求和本地/全局鼠标监听。
**Acceptance:** 默认 600 ms 仅触发一次；区内移动不重置；不请求 Accessibility。
**Verification:** HotCornerStateMachineTests + 前后台鼠标手测。
**Dependencies:** Task 2 · **Scope:** M

## Task 4: Full-screen Panel Prototype
**Outcome:** 320×400 pt 面板在全屏/Spaces 上方从角落生长并恢复焦点。
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
