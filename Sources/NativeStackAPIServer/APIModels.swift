import Foundation
import NativeStackCore

struct APISnapshot: Codable, Sendable {
    var systemStatus: SystemStatus
    var containers: [ContainerRecord]
    var images: [ImageRecord]
    var volumes: [VolumeRecord]
    var networks: [NetworkRecord]
    var composeProjects: [ComposeProjectRecord]
    var settings: AppSettings
    var filesBasePath: String
    var isInstalled: Bool
    var installPhase: String
    var isInstallingToolkit: Bool
    var lastError: String?
}

struct APILogsResponse: Codable, Sendable {
    var logs: String
}

struct APIStatsResponse: Codable, Sendable {
    var stats: ResourceStats
}

struct APIBatchBody: Codable, Sendable {
    var ids: [String]
    var force: Bool?
}

struct APICreateVolumeBody: Codable, Sendable {
    var name: String
}

struct APICreateNetworkBody: Codable, Sendable {
    var name: String
}

struct APIPullImageRequest: Codable, Sendable {
    var reference: String
}

struct APIDockerStatusResponse: Codable, Sendable {
    var status: DockerCompatibilityStatus
    var phase: String
    var isEnabling: Bool
}

extension ToolkitInstallPhase {
    var apiLabel: String { label }
}

extension DockerCompatibilityPhase {
    var apiLabel: String { label }
}
