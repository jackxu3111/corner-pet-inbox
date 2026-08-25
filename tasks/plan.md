# CornerPet MVP Implementation Plan

## Overview

构建 macOS 14+、Apple Silicon only 的原生角落想法收件箱。先证明 L 形热角、600 ms 停留、全屏悬浮、焦点恢复和可逆动画成立；通过风险门槛后，再交付草稿、事项、归档收藏、置顶、多显示器和宠物提醒。

## Source of Truth

- [产品定位](../docs/ideas/corner-pet-inbox.md)
- [已批准交互规格](../docs/superpowers/specs/2026-08-25-hot-corner-capture-interaction-design.md)
- [逐步 TDD 计划](../docs/superpowers/plans/2026-08-25-corner-pet-inbox-mvp.md)

## Architecture

- SwiftUI：输入、列表、设置、小猫；AppKit：鼠标、NSPanel、全屏、Spaces、显示器。
- SwiftData：唯一草稿与正式事项；UserDefaults：设置和不含文本的指标。
- 几何、停留、面板生命周期、提醒均为纯状态机。
- 单窗口、单数据库；本地优先，不联网、不引入第三方依赖。

## Dependency Graph

~~~text
工程基线
  ├─ L 形几何 ─ 停留/鼠标 ─ 全屏面板/动画 ─ 面板生命周期 ─ 多显示器
  ├─ 数据模型 ─ 草稿恢复 ─ 条件提交 ─ 收件箱 ─ 归档/收藏/编辑
  └─ 设置 ─ 登录启动 ─ 提醒/休眠 ─ 小猫
汇合 → 双语/无障碍 → 本地指标 → QA → arm64 Release
~~~

## Phase 0: Native Risk Gate

- [ ] Task 1: macOS 14、arm64 工程与测试基线
- [ ] Task 2: 四角 43×6 pt L 形热区几何
- [ ] Task 3: 500/600/700 ms 停留与鼠标适配
- [ ] Task 4: 320×400 pt 全屏面板和角落生长动画原型

### Checkpoint A

- [ ] 四角几何和停留边界测试通过
- [ ] Finder、Safari/Xcode 全屏、其他 Space 均能呼出
- [ ] 焦点可靠获得并恢复
- [ ] 收纳可反向，无透明点击层
- [ ] 连续自用 30 分钟误触可接受
- [ ] Jack 批准后进入 Phase 1

## Phase 1: Reliable Capture Loop

- [ ] Task 5: SwiftData IdeaItem 与唯一 Draft
- [ ] Task 6: 自动聚焦、草稿恢复、Return 条件提交与错误恢复
- [ ] Task 7: 输入优先布局与收件箱
- [ ] Task 8: 归档、五秒撤销、收藏、搜索、编辑、永久删除

### Checkpoint B

- [ ] 草稿在外部点击、Escape、退出和重启后恢复
- [ ] 保存成功后才清空草稿
- [ ] Return 后鼠标在内保持、在外收回、置顶保持
- [ ] 保存失败保留文本并可重试
- [ ] 正式事项生命周期符合规格

## Phase 2: Window and System Integration

- [ ] Task 9: 面板状态机、120 ms 防抖、置顶移动缩放
- [ ] Task 10: 四角设置、主屏/所有屏与动态重排
- [ ] Task 11: 其余设置、冲突帮助、登录启动
- [ ] Task 12: 每日提醒、休眠补发、稍后提醒、小猫

### Checkpoint C

- [ ] 置顶/归位与缩放正确
- [ ] 屏幕变化无陈旧热区
- [ ] 置顶屏断开后窗口回主屏
- [ ] 登录启动隐藏运行
- [ ] 每日最多一次提醒，休眠只补一次

## Phase 3: Release Candidate

- [ ] Task 13: 中英文、无障碍、Reduce Motion、错误文案
- [ ] Task 14: 本地指标、自动化、QA、arm64 Release

### Checkpoint D

- [ ] 全自动化通过
- [ ] 双语无 raw key、截断或不可点控件
- [ ] Reduce Motion 行为一致
- [ ] Release arm64 构建成功
- [ ] 启动七天自用验证

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| 热角误触 | High | 43×6 pt L 形、三档停留、Phase 0 验证 |
| 全屏/焦点异常 | High | AppKit 原型先行，跨应用实测 |
| 草稿丢失 | High | 独立 DraftStore，成功提交后才清空 |
| 状态冲突 | High | 单一 PanelStateMachine |
| 多屏陈旧坐标 | High | 不缓存 NSScreen，变化即重建 |
| 动画拖慢记录 | Medium | 260/180 ms、可反向、Reduce Motion 120 ms |
| 宠物疲劳 | Medium | 每日一次、十分钟稍后、允许关闭 |
| 范围膨胀 | High | 严格执行规格 Not Doing |

## Execution Policy

- Phase 0 是强制风险门槛。
- 每个任务执行红灯测试 → 最小实现 → 绿灯测试 → 构建检查。
- 每 3–4 个任务人工验收。
- 未经 Jack 授权，不提交、不推送、不创建 PR。
