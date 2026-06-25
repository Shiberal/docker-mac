import Foundation

public enum ContainerState: String, Codable, Sendable, CaseIterable {
    case created
    case running
    case paused
    case stopped
    case exited
    case dead
    case unknown

    public var isActive: Bool { self == .running }
}

public struct ContainerRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String?
    public var image: String
    public var state: ContainerState
    public var status: String?
    public var ports: [String]
    public var createdAt: Date?
    public var ipAddress: String?

    public init(
        id: String,
        name: String? = nil,
        image: String,
        state: ContainerState,
        status: String? = nil,
        ports: [String] = [],
        createdAt: Date? = nil,
        ipAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.createdAt = createdAt
        self.ipAddress = ipAddress
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return String(id.prefix(12))
    }
}

public struct ImageRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var repository: String
    public var tag: String
    public var sizeBytes: UInt64?
    public var createdAt: Date?

    public init(
        id: String,
        repository: String,
        tag: String,
        sizeBytes: UInt64? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.repository = repository
        self.tag = tag
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }

    public var reference: String {
        tag.isEmpty || tag == "<none>" ? repository : "\(repository):\(tag)"
    }
}

public enum EngineState: String, Codable, Sendable {
    case running
    case stopped
    case starting
    case error
    case notInstalled
}

public struct SystemStatus: Codable, Sendable {
    public var engineState: EngineState
    public var version: String?
    public var runningContainers: Int
    public var totalContainers: Int
    public var message: String?

    public init(
        engineState: EngineState,
        version: String? = nil,
        runningContainers: Int = 0,
        totalContainers: Int = 0,
        message: String? = nil
    ) {
        self.engineState = engineState
        self.version = version
        self.runningContainers = runningContainers
        self.totalContainers = totalContainers
        self.message = message
    }
}

public struct LogLine: Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let timestamp: Date

    public init(id: UUID = UUID(), text: String, timestamp: Date = .now) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

public struct ResourceStats: Sendable {
    public var cpuPercent: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryLimitBytes: UInt64?

    public init(
        cpuPercent: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
    }
}
