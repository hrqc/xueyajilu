import Foundation

/// 本地优先同步抽象。默认实现不联网，未来可替换为 iCloud/CloudKit 适配器。
public protocol ReadingSyncService: Sendable {
    func push(_ readings: [ExportReading]) async throws
    func pull(since: Date?) async throws -> [ExportReading]
}

/// 默认空同步实现，保证未授权云同步时所有数据仍留在本地。
public struct LocalOnlySyncService: ReadingSyncService, Sendable {
    public init() {}
    public func push(_ readings: [ExportReading]) async throws {}
    public func pull(since: Date?) async throws -> [ExportReading] { [] }
}
