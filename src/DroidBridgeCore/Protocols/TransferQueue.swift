import Foundation

/// Interface for managing the asynchronous queue of transfer jobs.
public protocol TransferQueue: Sendable {
    /// Enqueues a new transfer job for execution.
    func enqueue(job: TransferJob) async -> UUID
    
    /// Pauses an active or pending transfer job.
    func pause(jobID: UUID) async throws
    
    /// Resumes a paused transfer job.
    func resume(jobID: UUID) async throws
    
    /// Cancels an active or queued transfer job.
    func cancel(jobID: UUID) async throws
    
    /// Returns a snapshot of all tracked jobs.
    func allJobs() async -> [TransferJob]
    
    /// Returns the current state of a specific job.
    func job(for id: UUID) async -> TransferJob?
}
