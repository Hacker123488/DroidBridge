import XCTest
@testable import DroidBridgeCore

final class TransferStateTests: XCTestCase {
    func testQueueLifecyclePendingToCompleted() async throws {
        let queue = TransferQueueService()
        
        let job = TransferJob(
            name: "sample.pdf",
            direction: .macToAndroid,
            localURL: URL(fileURLWithPath: "/tmp/sample.pdf"),
            remotePath: "/sdcard/Documents/sample.pdf",
            size: 1024
        )
        
        let jobID = await queue.enqueue(job: job)
        let enqueuedJob = await queue.job(for: jobID)
        XCTAssertEqual(enqueuedJob?.state, .pending)
        
        await queue.updateJobState(id: jobID, state: .inProgress(fractionCompleted: 0.5, speedBytesPerSec: 5000000))
        let inProgressJob = await queue.job(for: jobID)
        if case .inProgress(let fraction, _) = inProgressJob?.state {
            XCTAssertEqual(fraction, 0.5)
        } else {
            XCTFail("State should be inProgress")
        }
        
        await queue.updateJobState(id: jobID, state: .completed)
        let completedJob = await queue.job(for: jobID)
        XCTAssertEqual(completedJob?.state, .completed)
    }
    
    func testPauseAndResumeJob() async throws {
        let queue = TransferQueueService()
        let job = TransferJob(
            name: "video.mp4",
            direction: .macToAndroid,
            localURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            remotePath: "/sdcard/Movies/video.mp4",
            size: 50000000
        )
        
        let jobID = await queue.enqueue(job: job)
        await queue.updateJobState(id: jobID, state: .inProgress(fractionCompleted: 0.3, speedBytesPerSec: 1000000))
        
        try await queue.pause(jobID: jobID)
        let pausedJob = await queue.job(for: jobID)
        if case .paused(let fraction) = pausedJob?.state {
            XCTAssertEqual(fraction, 0.3)
        } else {
            XCTFail("Job should be paused")
        }
        
        try await queue.resume(jobID: jobID)
        let resumedJob = await queue.job(for: jobID)
        if case .inProgress(let fraction, _) = resumedJob?.state {
            XCTAssertEqual(fraction, 0.3)
        } else {
            XCTFail("Job should resume to inProgress")
        }
    }
}
