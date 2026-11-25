// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// #1223: bekçinin açma denemesi ile kurulum aynı TV'ye aynı anda geliştirici bağlantısı açıyor, TV bağlantıyı zorla
/// kapatıyordu; "güncelle"ye üç kez basılınca üç kurulum başlıyordu. TV başına tek kanal (Windows TvLaneTests ve Android
/// TvLaneTest ile aynı).
final class TVLaneTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var running = 0
        var most = 0
        var lines: [String] = []
        var started = 0
        func add(_ line: String) { lock.withLock { lines.append(line) } }
    }

    func testSameTVRunsOneOperationAtATime() {
        let lane = TVLane()
        let box = Box()
        DispatchQueue.concurrentPerform(iterations: 4) { index in
            lane.run(host: index % 2 == 0 ? "192.168.1.147" : " 192.168.1.147 ", "açma") {
                box.lock.withLock { box.running += 1; box.most = max(box.most, box.running) }
                Thread.sleep(forTimeInterval: 0.03)
                box.lock.withLock { box.running -= 1 }
            }
        }
        XCTAssertEqual(box.most, 1)
    }

    func testDifferentTVsDoNotWaitForEachOther() {
        let lane = TVLane()
        let release = DispatchSemaphore(value: 0)
        let first = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            lane.run(host: "192.168.1.10", "kurulum") { release.wait() }
            first.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)
        let started = Date()
        lane.run(host: "192.168.1.11", "açma") {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        release.signal()
        first.wait()
    }

    func testOpenWaitsWhileTheInstallIsRunning() {
        let lane = TVLane()
        let box = Box()
        let release = DispatchSemaphore(value: 0)
        let installDone = DispatchSemaphore(value: 0)
        var finished = false
        DispatchQueue.global().async {
            _ = try? lane.install(host: "tv") { () -> String in
                release.wait()
                box.lock.withLock { finished = true }
                return "0.9.104"
            }
            installDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(lane.isInstalling("tv"))
        let opened = DispatchSemaphore(value: 0)
        var openedDuringInstall: Bool?
        DispatchQueue.global().async {
            lane.run(host: "tv", "açma", log: box.add) { box.lock.withLock { openedDuringInstall = !finished } }
            opened.signal()
        }
        XCTAssertEqual(opened.wait(timeout: .now() + 0.15), .timedOut)
        release.signal()
        XCTAssertEqual(opened.wait(timeout: .now() + 5), .success)
        installDone.wait()
        XCTAssertEqual(openedDuringInstall, false)
        XCTAssertTrue(box.lines.contains { $0.contains("sırasını bekliyor") })
        XCTAssertFalse(lane.isInstalling("tv"))
    }

    func testSecondInstallRequestDoesNotStartANewInstall() throws {
        let lane = TVLane()
        let box = Box()
        let release = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        var results: [String] = []
        for _ in 0..<3 {
            group.enter()
            DispatchQueue.global().async {
                let value = try? lane.install(host: "tv", log: box.add) { () -> String in
                    box.lock.withLock { box.started += 1 }
                    release.wait()
                    return "0.9.104"
                }
                box.lock.withLock { results.append(value ?? "hata") }
                group.leave()
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
        release.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(box.started, 1)
        XCTAssertEqual(results, ["0.9.104", "0.9.104", "0.9.104"])
        XCTAssertEqual(box.lines.filter { $0.contains("yeni kurulum başlatılmadı") }.count, 2)
        // Kurulum bitince yeni istek yeniden kurar.
        _ = try lane.install(host: "tv") { () -> String in box.started += 1; return "x" }
        XCTAssertEqual(box.started, 2)
    }

    func testWaitingRequestGetsTheRunningInstallsError() {
        struct Broken: Error {}
        let lane = TVLane()
        let release = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let threw: Bool
            do { _ = try lane.install(host: "tv") { () throws -> Int in release.wait(); throw Broken() }; threw = false } catch { threw = true }
            XCTAssertTrue(threw)
            done.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)
        DispatchQueue.global().async { Thread.sleep(forTimeInterval: 0.05); release.signal() }
        XCTAssertThrowsError(try lane.install(host: "tv") { () -> Int in 5 }) { XCTAssertTrue($0 is Broken) }
        done.wait()
    }

    func testNestedCallOnTheSameTVDoesNotWait() throws {
        let lane = TVLane(maxWait: 30)
        let value = try lane.install(host: "tv") { lane.run(host: "tv", "açma") { 7 } }
        XCTAssertEqual(value, 7)
    }

    func testStuckOperationDoesNotBlockTheTVForever() {
        let lane = TVLane(maxWait: 0.1)
        let box = Box()
        let never = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { lane.run(host: "tv", "kurulum") { never.wait() } }
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(lane.run(host: "tv", "açma", log: box.add) { 3 }, 3)
        XCTAssertTrue(box.lines.contains { $0.contains("beklemeden başlıyor") })
        never.signal()
    }

    /// Mac'in yolu: yardımcı çağrıları async; kurulum sürerken açma bekler, ikinci kurulum sürenin sonucunu alır.
    func testAsyncCallsShareTheLane() async throws {
        let lane = TVLane()
        let box = Box()
        let gate = AsyncGate()
        async let first = lane.installAsync(host: "tv", log: box.add) { () -> String in
            box.lock.withLock { box.started += 1 }
            await gate.wait()
            return "0.9.104"
        }
        try await Task.sleep(for: .milliseconds(50))
        async let second = lane.installAsync(host: "tv", log: box.add) { () -> String in
            box.lock.withLock { box.started += 1 }
            return "ikinci"
        }
        async let open: Int = lane.runAsync(host: "tv", "açma", log: box.add) { 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(lane.isBusy("tv"))
        await gate.open()
        let results = try await [first, second]
        _ = await open
        XCTAssertEqual(results, ["0.9.104", "0.9.104"])
        XCTAssertEqual(box.started, 1)
        XCTAssertTrue(box.lines.contains { $0.contains("yeni kurulum başlatılmadı") })
        XCTAssertTrue(box.lines.contains { $0.contains("sırasını bekliyor") })
    }
}

/// Testlerde async bekleme kapısı.
actor AsyncGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
