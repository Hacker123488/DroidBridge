import Foundation

/// Swift Actor managing asynchronous file transfer scheduling and lifecycle state transitions.
public actor TransferQueueService: TransferQueue {
    private var jobs: [UUID: TransferJob] = [:]
    private var order: [UUID] = []
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var pausedJobs: Set<UUID> = []
    
    private let maxConcurrentTransfers: Int
    private var runningCount: Int = 0
    
    public init(maxConcurrentTransfers: Int = 2) {
        self.maxConcurrentTransfers = maxConcurrentTransfers
    }
    
    public func enqueue(job: TransferJob) async -> UUID {
        var newJob = job
        newJob.state = .pending
        newJob.updatedAt = Date()
        jobs[newJob.id] = newJob
        order.append(newJob.id)
        return newJob.id
    }
    
    public func updateJobState(id: UUID, state: TransferJobState) {
        guard var job = jobs[id] else { return }
        job.state = state
        job.updatedAt = Date()
        jobs[id] = job
    }
    
    public func pause(jobID: UUID) async throws {
        guard var job = jobs[jobID] else {
            throw DeviceError.itemNotFound(path: jobID.uuidString)
        }
        
        switch job.state {
        case .inProgress(let fraction, _):
            activeTasks[jobID]?.cancel()
            activeTasks.removeValue(forKey: jobID)
            pausedJobs.insert(jobID)
            job.state = .paused(fractionCompleted: fraction)
            job.updatedAt = Date()
            jobs[jobID] = job
        case .pending:
            pausedJobs.insert(jobID)
            job.state = .paused(fractionCompleted: 0)
            job.updatedAt = Date()
            jobs[jobID] = job
        default:
            break
        }
    }
    
    public func resume(jobID: UUID) async throws {
        guard var job = jobs[jobID] else {
            throw DeviceError.itemNotFound(path: jobID.uuidString)
        }
        
        guard pausedJobs.contains(jobID) else { return }
        pausedJobs.remove(jobID)
        
        if case .paused(let fraction) = job.state {
            job.state = .inProgress(fractionCompleted: fraction, speedBytesPerSec: 0)
            job.updatedAt = Date()
            jobs[jobID] = job
        } else {
            job.state = .pending
            job.updatedAt = Date()
            jobs[jobID] = job
        }
    }
    
    public func cancel(jobID: UUID) async throws {
        guard var job = jobs[jobID] else {
            throw DeviceError.itemNotFound(path: jobID.uuidString)
        }
        
        activeTasks[jobID]?.cancel()
        activeTasks.removeValue(forKey: jobID)
        pausedJobs.remove(jobID)
        
        job.state = .cancelled
        job.updatedAt = Date()
        jobs[jobID] = job
    }
    
    public func registerActiveTask(jobID: UUID, task: Task<Void, Never>) {
        activeTasks[jobID] = task
    }
    
    public func allJobs() async -> [TransferJob] {
        order.compactMap { jobs[$0] }
    }
    
    public func job(for id: UUID) async -> TransferJob? {
        jobs[id]
    }
}
