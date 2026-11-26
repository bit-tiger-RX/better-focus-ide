// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import XCTest
@testable import BetterFocusIDE

/// 进行中的进度被 60 秒闲置清扫丢掉之后，下一次增量回写只剩两项。
/// 这里锁住「至少留 30 分钟」和「收起后仍能把整表合并回来」。
final class TodoIdleTests: XCTestCase {

    func testInProgressIdleIgnoresTheOneMinuteSetting() {
        XCTAssertEqual(
            TodoController.idleClearInterval(configured: 60, inProgress: true),
            TodoController.inProgressIdleFloor)
        XCTAssertGreaterThan(TodoController.inProgressIdleFloor, 60)
        XCTAssertEqual(
            TodoController.idleClearInterval(configured: 60, inProgress: false),
            60)
        XCTAssertEqual(
            TodoController.idleClearInterval(configured: 3600, inProgress: true),
            3600)
    }

    /// 11 项做到第二项时被闲置收起；第二项完成只回写两条，总数仍是 11。
    func testCompletionAfterIdleKeepsTheOriginalTotal() {
        let ctrl = TodoController()
        ctrl.apply(snapshot: elevenTasks(active: 2), sessionID: "s", provider: .qoder,
                   providerName: "Qoder", project: "demo")
        XCTAssertEqual(ctrl.progress.countText, "1 / 11")

        ctrl.suspendForIdle()
        XCTAssertFalse(ctrl.hasTodo)

        ctrl.ingest(payload: itemPayload(id: "t2", content: "任务 2", status: "completed"),
                    sessionID: "s", provider: .qoder, providerName: "Qoder", project: "demo")
        ctrl.ingest(payload: itemPayload(id: "t3", content: "任务 3", status: "in_progress"),
                    sessionID: "s", provider: .qoder, providerName: "Qoder", project: "demo")

        XCTAssertEqual(ctrl.progress.total, 11)
        XCTAssertEqual(ctrl.progress.completed, 2)
        XCTAssertEqual(ctrl.progress.current?.id, "t3")
        XCTAssertEqual(ctrl.items.first { $0.id == "t2" }?.status, .completed)
        XCTAssertEqual(ctrl.items.first { $0.id == "t11" }?.status, .pending)
    }

    func testSessionEndDropsTheSuspendedList() {
        let ctrl = TodoController()
        ctrl.apply(snapshot: elevenTasks(active: 2), sessionID: "s", provider: .qoder,
                   providerName: "Qoder", project: "demo")
        ctrl.suspendForIdle()
        ctrl.handleSessionEnded("s")

        ctrl.upsert(TodoItem(id: "t2", content: "任务 2", status: .completed),
                    sessionID: "s", provider: .qoder, providerName: "Qoder", project: "demo")
        XCTAssertEqual(ctrl.progress.total, 1)
    }

    func testAnotherSessionDoesNotRestoreTheOldList() {
        let ctrl = TodoController()
        ctrl.apply(snapshot: elevenTasks(active: 2), sessionID: "s", provider: .qoder,
                   providerName: "Qoder", project: "demo")
        ctrl.suspendForIdle()

        ctrl.upsert(TodoItem(id: "n1", content: "别的会话", status: .inProgress),
                    sessionID: "other", provider: .qoder, providerName: "Qoder", project: "demo")
        XCTAssertEqual(ctrl.progress.total, 1)
        XCTAssertEqual(ctrl.items.first?.id, "n1")
    }

    private func elevenTasks(active: Int) -> [TodoItem] {
        (1...11).map { index in
            let status: TodoStatus
            if index < active { status = .completed }
            else if index == active { status = .inProgress }
            else { status = .pending }
            return TodoItem(id: "t\(index)", content: "任务 \(index)", status: status)
        }
    }

    private func itemPayload(id: String, content: String, status: String) -> [String: AnyCodableValue] {
        [
            "todo": .dictionary([
                "id": .string(id),
                "content": .string(content),
                "status": .string(status),
            ]),
        ]
    }
}
