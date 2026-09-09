import XCTest
import Foundation
import TempoInput
import TempoCore

final class InputTests: XCTestCase {
    func testSilentPCMThroughAsynchronousWorker() async {
        let input = AudioInput()
        let started = expectation(description: "Worker started")
        let steady = expectation(description: "Real PCM reached stable detector")
        steady.assertForOverFulfill = false
        input.start(device: nil, channel: 1, settings: .init()) { update in
            switch update {
            case .started(let rate): XCTAssertEqual(rate, 48_000); started.fulfill()
            case .measurement(let snapshot, _, _, _):
                if snapshot.reading.isStable {
                    XCTAssertEqual(snapshot.reading.pulseMilliseconds!, 500, accuracy: 0.1)
                    steady.fulfill()
                }
            case .failed(let error): XCTFail(error)
            }
        }
        await fulfillment(of: [started, steady], timeout: 6)
        let stopped = expectation(description: "Stop completed")
        input.stop { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testStopPreventsFurtherCallbacksAndRestartStartsFresh() async {
        let input = AudioInput()
        let callbacks = CallbackCounter()
        let started = expectation(description: "Started")
        input.start(device: nil, channel: 1, settings: .init()) { update in
            callbacks.increment()
            if case .started = update { started.fulfill() }
        }
        await fulfillment(of: [started], timeout: 2)
        let stopped = expectation(description: "Stop completed")
        input.stop { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 2)
        let countAfterStop = callbacks.value
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(callbacks.value, countAfterStop)
        let fresh = expectation(description: "Restarted with fresh tracker")
        fresh.assertForOverFulfill = false
        input.start(device: nil, channel: 1, settings: .init()) { update in
            if case .measurement(let snapshot, _, _, _) = update, snapshot.reading.pulseCount == 1 {
                XCTAssertNil(snapshot.reading.pulseMilliseconds)
                fresh.fulfill()
            }
        }
        await fulfillment(of: [fresh], timeout: 2)
        let done = expectation(description: "Second stop completed")
        input.stop { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
    }

    func testInvalidChannelFailsWithoutOpeningCapture() async {
        let input = AudioInput()
        let failed = expectation(description: "Invalid channel rejected")
        input.start(device: nil, channel: 0, settings: .init()) { update in
            if case .failed = update { failed.fulfill() } else { XCTFail("Invalid source started") }
        }
        await fulfillment(of: [failed], timeout: 2)
    }

    #if os(Linux)
    func testHardwareEnumerationExplicitlyUnavailableOnLinux() async {
        let input = AudioInput()
        let finished = expectation(description: "Hardware error reported")
        input.devices { result in
            if case .success = result { XCTFail("Linux must not masquerade as a Core Audio input") }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }
    #endif
}

private final class CallbackCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
