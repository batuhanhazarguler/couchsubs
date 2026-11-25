// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Android TV bekçisi Samsung'daki #1248 yolunu izler: uygulama TV'de çalışıyor ama 10 sn'de bağlanmıyorsa bir kez
/// kapatılıp (am force-stop) temiz açılır; bağlanırsa dokunulmaz (Windows AndroidTvLauncherTests ve Android
/// AndroidTvLauncherTest ile aynı).
final class AndroidTVLauncherTests: XCTestCase {
    private let started = "Starting: Intent { cmp=com.couchsubs.tv/.MainActivity }"
    private let broughtToFront = "Starting: Intent { cmp=com.couchsubs.tv/.MainActivity }\nWarning: Activity not started, its current task has been brought to the front"

    func testRecognisesARunningApp() {
        XCTAssertTrue(AndroidTVLauncher.isResumed(AndroidTVApp.alreadyRunning))
        XCTAssertTrue(AndroidTVLauncher.isResumed(broughtToFront))
        XCTAssertTrue(AndroidTVLauncher.isResumed("Warning: Activity not started, intent has been delivered to currently running top-most instance."))
        XCTAssertFalse(AndroidTVLauncher.isResumed(started))
        XCTAssertFalse(AndroidTVLauncher.isResumed(""))
    }

    func testClosedAppIsOpenedOnce() throws {
        var opens: [Bool] = []
        let output = try AndroidTVLauncher.openBlocking({ opens.append($0); return self.started }, appConnected: { false },
                                                         resumeWait: 0.05, poll: 0.005)
        XCTAssertEqual(opens, [false])
        XCTAssertEqual(output, started)
    }

    func testRunningAppThatConnectsIsLeftAlone() throws {
        var opens: [Bool] = []
        var polls = 0
        let output = try AndroidTVLauncher.openBlocking({ opens.append($0); return AndroidTVApp.alreadyRunning },
                                                         appConnected: { polls += 1; return polls > 2 }, resumeWait: 5, poll: 0.005)
        XCTAssertEqual(output, AndroidTVApp.alreadyRunning)
        XCTAssertEqual(opens, [false])
    }

    func testRunningAppThatDoesNotConnectIsForceStoppedAndStartedOnce() throws {
        var opens: [Bool] = []
        var lines: [String] = []
        let output = try AndroidTVLauncher.openBlocking({ restart in
            opens.append(restart)
            return restart ? self.started : AndroidTVApp.alreadyRunning
        }, appConnected: { false }, resumeWait: 0.05, poll: 0.005, log: { lines.append($0) })
        XCTAssertEqual(opens, [false, true])
        XCTAssertEqual(output, started)
        XCTAssertTrue(lines.contains { $0.contains("am force-stop") })
    }

    func testBroughtToFrontAlsoCountsAsRunning() throws {
        var opens: [Bool] = []
        _ = try AndroidTVLauncher.openBlocking({ opens.append($0); return $0 ? self.started : self.broughtToFront },
                                               appConnected: { false }, resumeWait: 0.03, poll: 0.005)
        XCTAssertEqual(opens, [false, true])
    }

    func testFailureIsNotRetriedHere() {
        struct Closed: Error {}
        var opens: [Bool] = []
        XCTAssertThrowsError(try AndroidTVLauncher.openBlocking({ opens.append($0); throw Closed() }, appConnected: { false },
                                                                resumeWait: 0.03))
        XCTAssertEqual(opens, [false])
    }

    /// Mac'in async yolu da aynı sırayı izler.
    func testAsyncPathRestartsOnce() async throws {
        let opens = OpenLog()
        let output = try await AndroidTVLauncher.open({ restart in
            await opens.add(restart)
            return restart ? "Starting: Intent" : AndroidTVApp.alreadyRunning
        }, appConnected: { false }, resumeWait: .milliseconds(50), poll: .milliseconds(5))
        let seen = await opens.values
        XCTAssertEqual(seen, [false, true])
        XCTAssertEqual(output, "Starting: Intent")
    }

    func testAsyncPathLeavesAConnectedAppAlone() async throws {
        let opens = OpenLog()
        _ = try await AndroidTVLauncher.open({ restart in
            await opens.add(restart)
            return AndroidTVApp.alreadyRunning
        }, appConnected: { true }, resumeWait: .milliseconds(50), poll: .milliseconds(5))
        let seen = await opens.values
        XCTAssertEqual(seen, [false])
    }
}

private actor OpenLog {
    var values: [Bool] = []
    func add(_ value: Bool) { values.append(value) }
}
