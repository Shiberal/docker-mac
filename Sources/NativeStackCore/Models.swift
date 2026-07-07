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
    public var composeProject: String?
    public var composeService: String?
    public var mounts: [String]
    public var platform: String?

    public init(
        id: String,
        name: String? = nil,
        image: String,
        state: ContainerState,
        status: String? = nil,
        ports: [String] = [],
        createdAt: Date? = nil,
        ipAddress: String? = nil,
        composeProject: String? = nil,
        composeService: String? = nil,
        mounts: [String] = [],
        platform: String? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.createdAt = createdAt
        self.ipAddress = ipAddress
        self.composeProject = composeProject
        self.composeService = composeService
        self.mounts = mounts
        self.platform = platform
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

public struct ResourceStats: Codable, Sendable {
    public var cpuPercent: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryLimitBytes: UInt64?
    public var networkRxBytes: UInt64?
    public var networkTxBytes: UInt64?
    public var diskReadBytes: UInt64?
    public var diskWriteBytes: UInt64?
    public var storageUsedBytes: UInt64?

    public init(
        cpuPercent: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil,
        networkRxBytes: UInt64? = nil,
        networkTxBytes: UInt64? = nil,
        diskReadBytes: UInt64? = nil,
        diskWriteBytes: UInt64? = nil,
        storageUsedBytes: UInt64? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.networkRxBytes = networkRxBytes
        self.networkTxBytes = networkTxBytes
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
        self.storageUsedBytes = storageUsedBytes
    }
}

public struct ContainerResourceStat: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String?
    public var cpuPercent: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryLimitBytes: UInt64?
    public var diskReadBytes: UInt64?
    public var diskWriteBytes: UInt64?

    public init(
        id: String,
        name: String? = nil,
        cpuPercent: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil,
        diskReadBytes: UInt64? = nil,
        diskWriteBytes: UInt64? = nil
    ) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
    }
}

public struct ActivityStats: Codable, Sendable {
    public var cpuPercent: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryLimitBytes: UInt64?
    public var storageUsedBytes: UInt64?
    public var storagePath: String?
    public var containers: [ContainerResourceStat]

    public init(
        cpuPercent: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil,
        storageUsedBytes: UInt64? = nil,
        storagePath: String? = nil,
        containers: [ContainerResourceStat] = []
    ) {
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.storageUsedBytes = storageUsedBytes
        self.storagePath = storagePath
        self.containers = containers
    }
}

public struct VolumeRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var driver: String?
    public var sizeBytes: UInt64?
    public var createdAt: Date?
    public var mountpoint: String?

    public init(
        id: String,
        name: String,
        driver: String? = nil,
        sizeBytes: UInt64? = nil,
        createdAt: Date? = nil,
        mountpoint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.driver = driver
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.mountpoint = mountpoint
    }
}

public struct NetworkRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var driver: String?
    public var scope: String?
    public var subnet: String?

    public init(
        id: String,
        name: String,
        driver: String? = nil,
        scope: String? = nil,
        subnet: String? = nil
    ) {
        self.id = id
        self.name = name
        self.driver = driver
        self.scope = scope
        self.subnet = subnet
    }
}

public struct ComposeProjectRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var status: String?
    public var configFiles: [String]
    public var containerCount: Int
    public var runningCount: Int

    public init(
        id: String,
        name: String,
        status: String? = nil,
        configFiles: [String] = [],
        containerCount: Int = 0,
        runningCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.configFiles = configFiles
        self.containerCount = containerCount
        self.runningCount = runningCount
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var autoRefresh: Bool
    public var autoRefreshIntervalSeconds: Int
    public var dnsDomain: String
    public var terminalFontSize: Int
    public var logFontSize: Int
    public var hideDataVolume: Bool
    public var enableIPv6: Bool
    public var listSortField: String
    public var listSortAscending: Bool

    public init(
        autoRefresh: Bool = true,
        autoRefreshIntervalSeconds: Int = 10,
        dnsDomain: String = "nativestack.local",
        terminalFontSize: Int = 12,
        logFontSize: Int = 12,
        hideDataVolume: Bool = false,
        enableIPv6: Bool = false,
        listSortField: String = "name",
        listSortAscending: Bool = true
    ) {
        self.autoRefresh = autoRefresh
        self.autoRefreshIntervalSeconds = autoRefreshIntervalSeconds
        self.dnsDomain = dnsDomain
        self.terminalFontSize = terminalFontSize
        self.logFontSize = logFontSize
        self.hideDataVolume = hideDataVolume
        self.enableIPv6 = enableIPv6
        self.listSortField = listSortField
        self.listSortAscending = listSortAscending
    }

    public static let defaults = AppSettings()
}
