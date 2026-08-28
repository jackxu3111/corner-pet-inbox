# Task 5 Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Luna max implements one task at a time; Terra high reviews each stage gate before the next task begins.

**Goal:** Add a local SwiftData persistence foundation for one recoverable `Draft` and duplicate-permitting `IdeaItem` records, with deterministic stores and restart-recovery evidence.

**Architecture:** `Draft` and `IdeaItem` are SwiftData models behind focused `DraftStore` and `ItemStore` interfaces; SwiftUI and AppKit do not access `ModelContext` directly. `ModelContainerFactory` creates either the production local container or isolated test containers, while draft write debouncing is injected so tests never sleep.

**Tech Stack:** Swift 6, SwiftData, Foundation, XCTest, Xcode 27 beta toolchain; no third-party dependencies

**Spec:** `docs/superpowers/specs/2026-08-25-hot-corner-capture-interaction-design.md`

## Global Constraints

- Work in `/Users/jack/MyApp/CornerPet`; preserve the current dirty worktree and do not create a second worktree.
- Do not commit, push, create a PR, discard, regenerate, or blanket-revert existing files. Every commit-like step is a checkpoint that waits for Jack's explicit authorization.
- Minimum platform is macOS 14 Sonoma; architecture is Apple Silicon arm64 only; language mode is Swift 6.
- Product UI remains AppKit + SwiftUI; persistence uses SwiftData and Foundation only.
- All content is local-only: no account, cloud sync, network access, telemetry text, or third-party dependency.
- Preserve the fixed 0.400-second trigger, the `86×20 + 20×86 pt` top-left trigger arms, and the 0.100-second trigger-plus-panel close debounce already present in the dirty worktree.
- Preserve the 360×450 pt unpinned panel flush with the screen's left edge and the menu bar's lower edge.
- Task 5 adds no capture interface, keyboard behavior, navigation, archive/favorite/settings page, pinning implementation, or item lifecycle action.
- Draft text is a singleton separate from formal items; duplicates are allowed; normalized empty text never becomes an `IdeaItem`; a failed item save never clears the draft.
- The shell must use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` per command; do not change global `xcode-select` state.
- The project uses explicit `PBXGroup`, `PBXFileReference`, `PBXBuildFile`, and source-build-phase entries. Add surgical references with new unique 24-character IDs; do not convert groups, regenerate the project, or alter signing settings.

---

## Existing Baseline and Ownership

Before every implementation task, run:

```bash
git status --short
git diff --check
```

Expected: the known Task 1–4/trigger-rewrite changes remain present, including modified `project.pbxproj`, App/HotCorner files and untracked Panel/trigger files. No task in this plan may restore them.

Current contracts that Task 5 must not change:

```swift
enum DwellTiming { static let duration: TimeInterval = 0.4 }
struct PanelPositioner {
    static let defaultSize = CGSize(width: 360, height: 450)
    static let edgeInset: CGFloat = 0
}
```

Known verification behavior:

- Direct XCTest is the reliable unit path and currently passes 57/57 tests.
- A full-scheme `xcodebuild test` may stall during test worker materialization. It is supplementary evidence, not a replacement for direct XCTest.
- Do not delete `DerivedData` as a routine step; it is not required for the red/green cycle and may hide the known runner limitation.

## File Responsibility Map

| File | Responsibility |
|---|---|
| `CornerPet/Persistence/Draft.swift` | Singleton draft SwiftData model and immutable snapshot |
| `CornerPet/Persistence/IdeaItem.swift` | Formal item model, bucket representation, immutable snapshot |
| `CornerPet/Persistence/ModelContainerFactory.swift` | Production, memory-only, and explicit-URL SwiftData container creation |
| `CornerPet/Persistence/DraftStore.swift` | Restore, stage, debounce, flush, and clear the one draft |
| `CornerPet/Persistence/ItemStore.swift` | Create normalized inbox items and fetch newest-first inbox snapshots |
| `CornerPetTests/ModelContainerFactoryTests.swift` | Schema construction and same-URL relaunch recovery |
| `CornerPetTests/DraftStoreTests.swift` | Singleton, debounce, flush, restore, and failed-write retention |
| `CornerPetTests/ItemStoreTests.swift` | Empty rejection, trimming, duplicates, ordering, and save failure |
| `CornerPet.xcodeproj/project.pbxproj` | Explicit groups, file references, and target memberships only |

## Stable Interfaces Produced for Tasks 6 and 7

Implement these names and signatures exactly so later plans do not infer persistence details:

```swift
import Foundation
import SwiftData

@Model
final class Draft {
    var text: String
    var updatedAt: Date

    init(text: String = "", updatedAt: Date = .distantPast)
}

struct DraftSnapshot: Equatable {
    let text: String
    let updatedAt: Date
}

enum ItemBucket: String, Codable, CaseIterable {
    case inbox
    case archive
    case favorite
}

@Model
final class IdeaItem {
    @Attribute(.unique) var id: UUID
    var text: String
    var bucketRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var movedAt: Date

    var bucket: ItemBucket { get set }

    init(
        id: UUID = UUID(),
        text: String,
        bucket: ItemBucket = .inbox,
        createdAt: Date,
        updatedAt: Date,
        movedAt: Date
    )
}

struct IdeaItemSnapshot: Identifiable, Equatable {
    let id: UUID
    let text: String
    let bucket: ItemBucket
    let createdAt: Date
    let updatedAt: Date
    let movedAt: Date
}

@MainActor
protocol DraftStoring: AnyObject {
    var onWriteFailure: ((Error) -> Void)? { get set }
    func restore() throws -> DraftSnapshot
    func stage(text: String, updatedAt: Date)
    func flush() throws
    func clear(updatedAt: Date) throws
}

@MainActor
protocol ItemStoring: AnyObject {
    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot?
    func fetchInbox() throws -> [IdeaItemSnapshot]
}

@MainActor
enum ModelContainerFactory {
    static func makeProduction() throws -> ModelContainer
    static func makeInMemory() throws -> ModelContainer
    static func make(at storeURL: URL) throws -> ModelContainer
}
```

`ItemStore.createInboxItem` is the persistence boundary: it trims only leading/trailing `.whitespacesAndNewlines`, returns `nil` for an empty normalized result, always creates a new UUID for non-empty input, saves before returning, and never reads or clears `Draft`. Task 6 owns the rule “item save succeeds, then draft clear.”

---

### Task 5.1: Add the SwiftData schema and explicit project references

**Files:**

- Create: `CornerPet/Persistence/Draft.swift`
- Create: `CornerPet/Persistence/IdeaItem.swift`
- Create: `CornerPetTests/ModelContainerFactoryTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: macOS 14 SwiftData runtime.
- Produces: `Draft`, `DraftSnapshot`, `ItemBucket`, `IdeaItem`, and `IdeaItemSnapshot` from the stable interface block.

- [ ] **Step 1: Protect user-owned changes and map PBX insertion points**

Run:

```bash
git status --short
rg -n 'PBXBuildFile section|PBXFileReference section|PBXGroup section|PBXSourcesBuildPhase section|CornerPetTests' CornerPet.xcodeproj/project.pbxproj
```

Expected: the project has manually enumerated App, HotCorner, Panel, and test groups. Record new IDs before editing and do not reuse an existing ID.

- [ ] **Step 2: Write schema red tests**

Create `CornerPetTests/ModelContainerFactoryTests.swift` with the first test:

```swift
import SwiftData
import XCTest

@testable import CornerPet

@MainActor
final class ModelContainerFactoryTests: XCTestCase {
    func testInMemoryContainerRegistersDraftAndIdeaItem() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_000)

        context.insert(Draft(text: "draft", updatedAt: date))
        context.insert(IdeaItem(
            text: "idea",
            createdAt: date,
            updatedAt: date,
            movedAt: date
        ))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<IdeaItem>()).count, 1)
    }
}
```

- [ ] **Step 3: Add only the new tests to the test target and verify RED**

Add a `Persistence` product group, the three initial file references, one test file reference, corresponding build files, and source memberships. Do not add `Draft.swift` or `IdeaItem.swift` content yet.

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing
```

Expected: build fails because `ModelContainerFactory`, `Draft`, and `IdeaItem` are undefined. A PBX parse failure is not the expected red state and must be fixed before proceeding.

- [ ] **Step 4: Implement the two model files minimally**

Use the stable signatures above. In `IdeaItem.swift`, make the computed bucket defensive:

```swift
var bucket: ItemBucket {
    get { ItemBucket(rawValue: bucketRawValue) ?? .inbox }
    set { bucketRawValue = newValue.rawValue }
}

var snapshot: IdeaItemSnapshot {
    IdeaItemSnapshot(
        id: id,
        text: text,
        bucket: bucket,
        createdAt: createdAt,
        updatedAt: updatedAt,
        movedAt: movedAt
    )
}
```

Add `var snapshot: DraftSnapshot` to `Draft` using its exact stored values. Do not add relationships, tags, delete rules, version history, CloudKit metadata, or a text-length limit.

- [ ] **Step 5: Verify the schema files compile as the remaining RED narrows**

Run the Step 3 command.

Expected: build still fails only because `ModelContainerFactory` is undefined; the two `@Model` files compile and have product-target membership.

- [ ] **Step 6: Checkpoint; do not commit**

Run:

```bash
git diff --check
git diff -- CornerPet/Persistence/Draft.swift CornerPet/Persistence/IdeaItem.swift \
  CornerPetTests/ModelContainerFactoryTests.swift CornerPet.xcodeproj/project.pbxproj
```

Expected: no signing/build-setting changes and no unrelated PBX reorder. Wait for the Luna stage to be reviewable; do not commit without Jack's authorization.

---

### Task 5.2: Build isolated containers and prove same-URL restart recovery

**Files:**

- Create: `CornerPet/Persistence/ModelContainerFactory.swift`
- Modify: `CornerPetTests/ModelContainerFactoryTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `Draft.self`, `IdeaItem.self`.
- Produces: the three `ModelContainerFactory` methods from the stable interface block.

- [ ] **Step 1: Add a restart-recovery red test**

Append this test and helper:

```swift
func testReopeningTheSameStoreURLRestoresDraftAndItem() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CornerPetTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("content.store")
    let date = Date(timeIntervalSince1970: 2_000)

    do {
        let first = try ModelContainerFactory.make(at: storeURL)
        let context = ModelContext(first)
        context.insert(Draft(text: "survives", updatedAt: date))
        context.insert(IdeaItem(
            text: "also survives",
            createdAt: date,
            updatedAt: date,
            movedAt: date
        ))
        try context.save()
    }

    let relaunched = try ModelContainerFactory.make(at: storeURL)
    let relaunchedContext = ModelContext(relaunched)
    XCTAssertEqual(try relaunchedContext.fetch(FetchDescriptor<Draft>()).map(\.text), ["survives"])
    XCTAssertEqual(try relaunchedContext.fetch(FetchDescriptor<IdeaItem>()).map(\.text), ["also survives"])
}
```

- [ ] **Step 2: Run the reliable RED path**

Run the Task 5.1 Step 3 build command.

Expected: build fails because the factory is still missing.

- [ ] **Step 3: Implement `ModelContainerFactory`**

Use one schema and three configurations:

```swift
import SwiftData

@MainActor
enum ModelContainerFactory {
    private static var schema: Schema {
        Schema([Draft.self, IdeaItem.self])
    }

    static func makeProduction() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetContent",
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func make(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CornerPetContent",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

These initializer labels match the installed Xcode 27 SwiftData interface. Do not replace the explicit-URL test with UserDefaults or an in-memory approximation.

- [ ] **Step 4: Build and run direct XCTest to GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing

DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest \
/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected: `build-for-testing` succeeds and direct XCTest reports all prior 57 tests plus both container tests passing.

- [ ] **Step 5: Checkpoint; do not commit**

Inspect the model store files and PBX diff. Confirm the production configuration is not memory-only and no CloudKit database is configured. Wait for review; do not commit.

---

### Task 5.3: Implement deterministic singleton draft persistence

**Files:**

- Create: `CornerPet/Persistence/DraftStore.swift`
- Create: `CornerPetTests/DraftStoreTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: one `ModelContext`, injected draft-write scheduler, `Draft` model.
- Produces: `DraftStoring`, `DraftStore`, `DraftWriteScheduling`, and `DraftWriteCancellation`.

- [ ] **Step 1: Write draft lifecycle tests with a manual scheduler**

Create a `@MainActor` test double that records one cancellation token per scheduled write. Add these exact behaviors:

```swift
func testRestoreCreatesAndReusesExactlyOneEmptyDraft() throws
func testStageDebouncesAndOnlyLatestTextIsFlushed() throws
func testExplicitFlushPersistsImmediatelyAndCancelsPendingWrite() throws
func testClearPersistsEmptyDraftWithoutCreatingAnItem() throws
func testExistingDuplicateDraftRowsCollapseToNewestUpdatedAt() throws
func testFailedFlushKeepsPendingTextAndReportsWriteFailure() throws
```

The debounce test must assert persisted and staged state separately:

```swift
let scheduler = ManualDraftWriteScheduler()
let store = DraftStore(context: context, scheduler: scheduler, debounce: 0.250)
store.stage(text: "first", updatedAt: Date(timeIntervalSince1970: 10))
store.stage(text: "second", updatedAt: Date(timeIntervalSince1970: 11))

XCTAssertTrue(scheduler.tokens[0].isCancelled)
XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).first?.text, "")
scheduler.fire(1)
XCTAssertEqual(try store.restore().text, "second")
XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 1)
```

For the failure test, inject an internal `save: (ModelContext) throws -> Void` closure that throws `TestError.writeFailed`; assert `restore()` returns the pending text from memory and `onWriteFailure` receives the error.

- [ ] **Step 2: Add explicit target memberships and verify RED**

Add `DraftStore.swift` to the product and `DraftStoreTests.swift` to the unit target, then run `build-for-testing`.

Expected: compile fails because `DraftStoring`, `DraftStore`, and scheduler contracts do not exist.

- [ ] **Step 3: Implement the scheduler and store**

Use this constructor and state shape:

```swift
@MainActor
final class DraftStore: DraftStoring {
    var onWriteFailure: ((Error) -> Void)?

    init(
        context: ModelContext,
        scheduler: DraftWriteScheduling = MainRunLoopDraftWriteScheduler(),
        debounce: TimeInterval = 0.250,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    )

    func restore() throws -> DraftSnapshot
    func stage(text: String, updatedAt: Date)
    func flush() throws
    func clear(updatedAt: Date) throws
}
```

Store rules:

1. `restore()` returns pending memory text when a write is staged; otherwise it fetches all drafts sorted by `updatedAt` descending.
2. If no row exists, insert and save one empty draft.
3. If more than one row exists, keep the newest, delete the rest, and save once.
4. `stage` updates an in-memory `(text, updatedAt)`, cancels the prior token, and schedules exactly `debounce` seconds later.
5. Scheduled persistence calls the same throwing flush routine; on failure, keep the pending tuple and call `onWriteFailure` once.
6. `flush()` cancels the token, applies the pending tuple to the singleton, saves, and removes pending state only after save succeeds.
7. `clear` stages no timer; it cancels pending work, writes empty text with the supplied date, saves, and leaves exactly one draft.

Do not use `Task.sleep` in the store or tests.

- [ ] **Step 4: Run direct XCTest to GREEN**

Run the exact two-command build/direct-XCTest block from Task 5.2 Step 4.

Expected: all existing tests and six draft tests pass without real-time waits.

- [ ] **Step 5: Checkpoint; do not commit**

Run `git diff --check`; confirm `DraftStore` has no AppKit/SwiftUI import and no item creation method. Do not commit.

---

### Task 5.4: Implement item creation and newest-first inbox reads

**Files:**

- Create: `CornerPet/Persistence/ItemStore.swift`
- Create: `CornerPetTests/ItemStoreTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `ModelContext`, `IdeaItem`, `IdeaItemSnapshot`.
- Produces: `ItemStoring` and `ItemStore` using the stable signatures.

- [ ] **Step 1: Write formal-item persistence tests**

Create these tests:

```swift
func testWhitespaceOnlyCaptureReturnsNilAndCreatesNoItem() throws
func testCreateTrimsOnlyLeadingAndTrailingWhitespace() throws
func testDuplicateTextCreatesDistinctItems() throws
func testFetchInboxSortsCreatedAtNewestFirst() throws
func testFetchInboxExcludesArchiveAndFavoriteBuckets() throws
func testFailedSaveThrowsAndDoesNotReportSuccessfulSnapshot() throws
```

The duplicate test must prove both value and identity:

```swift
let first = try XCTUnwrap(store.createInboxItem(text: "same", at: firstDate))
let second = try XCTUnwrap(store.createInboxItem(text: "same", at: secondDate))
XCTAssertEqual(first.text, second.text)
XCTAssertNotEqual(first.id, second.id)
XCTAssertEqual(try store.fetchInbox().map(\.id), [second.id, first.id])
```

The failure test injects a `save` closure throwing `TestError.writeFailed`, then fetches through a fresh context to prove no durable item was claimed.

- [ ] **Step 2: Add project references and verify RED**

Add product/test memberships, run `build-for-testing`, and expect missing `ItemStoring`/`ItemStore` compile errors.

- [ ] **Step 3: Implement `ItemStore` minimally**

Use:

```swift
@MainActor
final class ItemStore: ItemStoring {
    init(
        context: ModelContext,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    )

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot?
    func fetchInbox() throws -> [IdeaItemSnapshot]
}
```

`fetchInbox` uses a predicate on `bucketRawValue == ItemBucket.inbox.rawValue` and sort descriptors `createdAt` descending, then `id` ascending as a deterministic tie-break. Creation uses one new model with `createdAt == updatedAt == movedAt == date`, calls the injected save, and returns a snapshot only after it succeeds. If save throws, delete the newly inserted unsaved model before rethrowing so the same context does not expose false success.

Do not add update, archive, favorite, search, edit, undo, or delete APIs; those belong to Task 8.

- [ ] **Step 4: Run direct XCTest and Debug build**

Run the exact direct-XCTest block from Task 5.2 Step 4, then:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData build
```

Expected: all persistence and prior tests pass; Debug ends in `BUILD SUCCEEDED`.

- [ ] **Step 5: Validate forbidden scope and checkpoint**

Run:

```bash
if rg -n 'CloudKit|URLSession|archiveItem|favoriteItem|deleteItem|search\(' \
  CornerPet/Persistence; then exit 1; fi
git diff --check
```

Expected: no matches and no whitespace errors. Do not commit; wait for Jack's authorization.

---

### Task 5.5: Task 5 stage gate and restart evidence

**Files:**

- Inspect only: all Task 5 files and `CornerPet.xcodeproj/project.pbxproj`
- No production or test edits unless verification exposes a specific defect

**Interfaces:**

- Consumes: complete Task 5 persistence layer.
- Produces: a reviewed handoff contract for Task 6.

- [ ] **Step 1: Run the complete reliable unit workflow from a fresh build-for-testing**

Run exactly:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing
DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected: direct XCTest passes all old and new tests; the count is at least 71 (57 baseline + 2 container + 6 draft + 6 item tests).

- [ ] **Step 2: Attempt the supplementary full scheme with a bounded observation window**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData test
```

Expected success case: `TEST SUCCEEDED`. Known environment case: unit work finishes but the runner stalls at worker materialization; record that exact limitation, stop the process cleanly, and do not classify already-passing direct unit tests as failed.

- [ ] **Step 3: Terra high reviews Task 5 against the specification**

Terra must verify:

- exactly one durable draft is restored and duplicate draft rows are repaired deterministically;
- empty normalized input creates no item;
- duplicate item text creates separate UUIDs;
- failed item persistence does not touch the draft;
- same explicit store URL survives container destruction/recreation;
- no Task 6/7/8 interface or UI was pulled forward;
- all new files have explicit product/test source membership and no signing setting changed.

Expected: no P0/P1 defect. Any defect returns to Luna with one focused red test before a fix.

- [ ] **Step 4: Record checkpoint; do not commit**

Run `git status --short` and report the exact Task 5 files. Wait for Jack's authorization; do not commit, push, or create a PR.

## Plan Self-Review

- **Specification coverage:** model fields, singleton draft, local persistence, empty rejection, duplicates, newest-first reads, failure retention, and restart recovery each map to a red/green task.
- **Scope control:** archive/favorites/search/edit/delete, submission UI, navigation, pinning, settings pages, and network work are absent.
- **Type consistency:** Tasks 6 and 7 consume `DraftStoring`, `ItemStoring`, `DraftSnapshot`, and `IdeaItemSnapshot` exactly as declared here.
- **Project integration:** every new source/test file is added through the existing explicit PBX reference strategy; project regeneration is prohibited.
- **Verification realism:** direct XCTest is authoritative; full scheme remains supplementary because worker materialization is a known harness limitation.
- **Checkpoint policy:** every former commit boundary is a review checkpoint and explicitly waits for Jack.
