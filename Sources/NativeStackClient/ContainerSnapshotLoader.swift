import Foundation
import NativeStackCore

struct ContainerSnapshot: Sendable {
    var systemStatus: SystemStatus
    var containers: [ContainerRecord]
    var images: [ImageRecord]
    var volumes: [VolumeRecord]
    var networks: [NetworkRecord]
    var composeProjects: [ComposeProjectRecord]
    var error: String?
}

enum ContainerSnapshotLoader {
    static func load(cli: ContainerCLI, all: Bool) async -> ContainerSnapshot {
        guard await cli.isInstalled() else {
            return ContainerSnapshot(
                systemStatus: SystemStatus(
                    engineState: .notInstalled,
                    message: "Install Apple's container tool from github.com/apple/container"
                ),
                containers: [],
                images: [],
                volumes: [],
                networks: [],
                composeProjects: [],
                error: nil
            )
        }

        do {
            let statusResult = try await cli.run(["system", "status"])
            var systemStatus = ContainerOutputParser.parseSystemStatus(
                stdout: statusResult.stdout,
                stderr: statusResult.stderr,
                containers: []
            )

            var containers: [ContainerRecord] = []
            var listArgs = ["list"]
            if all { listArgs.append("--all") }
            if let listOut = try? await cli.runOrThrow(listArgs) {
                containers = ContainerOutputParser.parseContainers(from: listOut, includeStopped: all)
                systemStatus.runningContainers = containers.filter(\.state.isActive).count
                systemStatus.totalContainers = containers.count
            }

            var images: [ImageRecord] = []
            if let imagesOut = try? await cli.runOrThrow(["image", "ls"]) {
                images = ContainerOutputParser.parseImages(from: imagesOut)
            }
            if await DockerResourceService.canQueryDocker() {
                let dockerImages = await DockerResourceService.listDockerImages()
                images = DockerResourceService.mergeImages(images, dockerImages)
            }

            var volumes: [VolumeRecord] = []
            if let volumesOut = try? await cli.runOrThrow(["volume", "ls"]) {
                volumes = ContainerOutputParser.parseVolumes(from: volumesOut)
            }
            if await DockerResourceService.canQueryDocker() {
                let dockerVolumes = await DockerResourceService.listDockerVolumes()
                volumes = DockerResourceService.mergeVolumes(volumes, dockerVolumes)
            }

            var networks: [NetworkRecord] = []
            if let networksOut = try? await cli.runOrThrow(["network", "ls"]) {
                networks = ContainerOutputParser.parseNetworks(from: networksOut)
            }
            if networks.isEmpty {
                networks = await DockerResourceService.listDockerNetworks()
            }

            containers = await DockerResourceService.enrichContainers(containers)

            let dockerCompose = await DockerResourceService.listComposeProjects()
            let containerCompose = await buildComposeProjects(from: containers)
            let composeProjects = mergeComposeProjects(docker: dockerCompose, containers: containerCompose)

            return ContainerSnapshot(
                systemStatus: systemStatus,
                containers: containers,
                images: images,
                volumes: volumes,
                networks: networks,
                composeProjects: composeProjects,
                error: nil
            )
        } catch {
            var snapshot = ContainerSnapshot(
                systemStatus: SystemStatus(engineState: .error, message: error.localizedDescription),
                containers: [],
                images: [],
                volumes: [],
                networks: [],
                composeProjects: [],
                error: error.localizedDescription
            )
            if let nsError = error as? NativeStackError,
               case .containerCLINotFound = nsError {
                snapshot.systemStatus = SystemStatus(
                    engineState: .notInstalled,
                    message: error.localizedDescription
                )
            }
            return snapshot
        }
    }

    private static func buildComposeProjects(from containers: [ContainerRecord]) async -> [ComposeProjectRecord] {
        let dockerCounts = await DockerResourceService.composeCountsFromDocker()
        var grouped: [String: (total: Int, running: Int, status: String?)] = [:]

        for container in containers {
            guard let project = container.composeProject else { continue }
            var entry = grouped[project] ?? (0, 0, nil)
            entry.total += 1
            if container.state.isActive {
                entry.running += 1
            }
            grouped[project] = entry
        }

        for (project, counts) in dockerCounts {
            var entry = grouped[project] ?? (0, 0, nil)
            entry.total = max(entry.total, counts.total)
            entry.running = max(entry.running, counts.running)
            if counts.running > 0 {
                entry.status = "running(\(counts.running))"
            }
            grouped[project] = entry
        }

        return grouped.map { name, counts in
            let status = counts.status ?? (counts.running > 0 ? "running(\(counts.running))" : "stopped")
            return ComposeProjectRecord(
                id: name,
                name: name,
                status: status,
                containerCount: max(counts.total, counts.running),
                runningCount: counts.running
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func mergeComposeProjects(
        docker: [ComposeProjectRecord],
        containers: [ComposeProjectRecord]
    ) -> [ComposeProjectRecord] {
        var merged: [String: ComposeProjectRecord] = [:]
        for project in docker {
            merged[project.name] = project
        }
        for project in containers {
            if let existing = merged[project.name] {
                merged[project.name] = ComposeProjectRecord(
                    id: existing.id,
                    name: existing.name,
                    status: existing.status ?? project.status,
                    configFiles: existing.configFiles.isEmpty ? project.configFiles : existing.configFiles,
                    containerCount: max(existing.containerCount, project.containerCount),
                    runningCount: max(existing.runningCount, project.runningCount)
                )
            } else {
                merged[project.name] = project
            }
        }
        return merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
