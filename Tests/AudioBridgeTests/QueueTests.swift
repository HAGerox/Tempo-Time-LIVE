import XCTest
import AudioBridge

final class QueueTests: XCTestCase {
    func testRoundTripAndTimestamp() throws {
        let queue = try XCTUnwrap(tt_queue_create()); defer { tt_queue_destroy(queue) }
        let input: [Float] = [-1, 0, 0.5, 1]
        XCTAssertEqual(tt_queue_write(queue, input, 4, 123.456), 1)
        var output = [Float](repeating: 0, count: 4), time = 0.0
        XCTAssertEqual(tt_queue_read(queue, &output, 4, &time), 4)
        XCTAssertEqual(output, input); XCTAssertEqual(time, 123.456)
        XCTAssertEqual(tt_queue_read(queue, &output, 4, &time), 0)
    }
    func testFullQueueDropsNewDataWithoutOverwritingUnreadData() throws {
        let queue = try XCTUnwrap(tt_queue_create()); defer { tt_queue_destroy(queue) }
        for i in 0..<Int(TT_QUEUE_BLOCKS) { XCTAssertEqual(tt_queue_write(queue, [Float(i)], 1, Double(i)), 1) }
        XCTAssertEqual(tt_queue_write(queue, [999], 1, 999), 0)
        XCTAssertEqual(tt_queue_dropped(queue), 1)
        var output: [Float] = [0], time = 0.0
        for i in 0..<Int(TT_QUEUE_BLOCKS) {
            XCTAssertEqual(tt_queue_read(queue, &output, 1, &time), 1)
            XCTAssertEqual(output[0], Float(i)); XCTAssertEqual(time, Double(i))
        }
    }
    func testWraparound() throws {
        let queue = try XCTUnwrap(tt_queue_create()); defer { tt_queue_destroy(queue) }
        var output: [Float] = [0], time = 0.0
        for i in 0..<10000 {
            XCTAssertEqual(tt_queue_write(queue, [Float(i)], 1, Double(i)), 1)
            XCTAssertEqual(tt_queue_read(queue, &output, 1, &time), 1)
            XCTAssertEqual(output[0], Float(i))
        }
    }
    func testShortReadDoesNotConsumeBlock() throws {
        let queue = try XCTUnwrap(tt_queue_create()); defer { tt_queue_destroy(queue) }
        XCTAssertEqual(tt_queue_write(queue, [1, 2, 3], 3, 5), 1)
        var output: [Float] = [0, 0, 0], time = 0.0
        XCTAssertEqual(tt_queue_read(queue, &output, 2, &time), 0)
        XCTAssertEqual(tt_queue_read(queue, &output, 3, &time), 3)
        XCTAssertEqual(output, [1, 2, 3])
    }
    func testInvalidWritesAreRejected() throws {
        let queue = try XCTUnwrap(tt_queue_create()); defer { tt_queue_destroy(queue) }
        XCTAssertEqual(tt_queue_write(queue, [1], 0, 0), 0)
        XCTAssertEqual(tt_queue_write(queue, [1], UInt32(TT_BLOCK_FRAMES + 1), 0), 0)
        XCTAssertEqual(tt_queue_write(queue, nil, 1, 0), 0)
    }
}
