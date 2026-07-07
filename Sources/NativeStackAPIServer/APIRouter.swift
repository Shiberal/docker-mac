import Foundation
import NativeStackClient
import NativeStackCore

@MainActor
public final class APIRouter {
    private let service: ContainerService

    public init(service: ContainerService) {
        self.service = service
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        if request.method == "OPTIONS" {
            return HTTPResponse(status: 204, headers: [:], body: Data())
        }

        switch (request.method, request.path) {
        case ("GET", "/api/health"):
            return .json(["ok": true])

        case ("GET", "/api/snapshot"), ("GET", "/api/status"):
            let all = request.path == "/api/status" || request.query["all"] == "true"
            await service.refresh(all: all)
            return .json(makeSnapshot())

        case ("GET", "/api/containers"):
            let all = request.query["all"] != "false"
            await service.refresh(all: all)
            return .json(service.containers)

        case ("GET", "/api/images"):
            await service.refresh(all: true)
            return .json(service.images)

        case ("GET", "/api/volumes"):
            await service.refresh(all: true)
            return .json(service.volumes)

        case ("GET", "/api/networks"):
            await service.refresh(all: true)
            return .json(service.networks)

        case ("GET", "/api/compose"):
            await service.refresh(all: true)
            return .json(service.composeProjects)

        case ("GET", "/api/activity/stats"):
            return .json(await service.activityStats())

        case ("GET", "/api/settings"):
            service.reloadSettings()
            return .json(service.settings)

        case ("POST", "/api/settings"):
            return await mutateSettings(request)

        case ("POST", "/api/engine/start"):
            return await mutate { try await service.startEngine() }

        case ("POST", "/api/engine/stop"):
            return await mutate { try await service.stopEngine() }

        case ("POST", "/api/toolkit/install"):
            return await mutate { try await service.installToolkit() }

        case ("POST", "/api/images/pull"):
            return await pullImage(request)

        case ("POST", "/api/docker/enable"):
            return await mutate { try await service.enableDockerCompatibility() }

        case ("GET", "/api/docker/status"):
            let status = await service.dockerStatus
            return .json(APIDockerStatusResponse(
                status: status,
                phase: service.dockerPhase.apiLabel,
                isEnabling: service.isEnablingDocker
            ))

        case ("POST", "/api/containers/run"):
            return await runContainer(request)

        case ("POST", "/api/containers/batch/start"):
            return await batchStart(request)

        case ("POST", "/api/containers/batch/stop"):
            return await batchStop(request)

        case ("DELETE", "/api/containers/batch"):
            return await batchRemove(request)

        case ("POST", "/api/volumes"):
            return await createVolume(request)

        case ("POST", "/api/networks"):
            return await createNetwork(request)

        default:
            return await handleDynamic(request)
        }
    }

    private func handleDynamic(_ request: HTTPRequest) async -> HTTPResponse {
        if request.method == "POST", request.path.hasPrefix("/api/containers/"), request.path.hasSuffix("/start") {
            let id = containerID(from: request.path, action: "start")
            return await mutate { try await service.startContainer(id: id) }
        }
        if request.method == "POST", request.path.hasPrefix("/api/containers/"), request.path.hasSuffix("/stop") {
            let id = containerID(from: request.path, action: "stop")
            return await mutate { try await service.stopContainer(id: id) }
        }
        if request.method == "POST", request.path.hasPrefix("/api/containers/"), request.path.hasSuffix("/restart") {
            let id = containerID(from: request.path, action: "restart")
            return await mutate { try await service.restartContainer(id: id) }
        }
        if request.method == "DELETE", request.path.hasPrefix("/api/containers/") {
            let id = String(request.path.dropFirst("/api/containers/".count))
            let force = request.query["force"] == "true"
            return await mutate { try await service.removeContainer(id: id, force: force) }
        }
        if request.method == "GET", request.path.hasPrefix("/api/containers/"), request.path.hasSuffix("/logs") {
            let prefix = request.path.dropFirst("/api/containers/".count)
            let id = String(prefix.dropLast("/logs".count))
            let tail = Int(request.query["tail"] ?? "200") ?? 200
            return await query {
                let logs = try await service.logs(for: id, tail: tail)
                return APILogsResponse(logs: logs)
            }
        }
        if request.method == "GET", request.path.hasPrefix("/api/containers/"), request.path.hasSuffix("/stats") {
            let prefix = request.path.dropFirst("/api/containers/".count)
            let id = String(prefix.dropLast("/stats".count))
            return await query {
                let stats = try await service.containerStats(id: id)
                return APIStatsResponse(stats: stats)
            }
        }
        if request.method == "GET", request.path.hasPrefix("/api/containers/"), request.path.hasSuffix("/files") {
            let prefix = request.path.dropFirst("/api/containers/".count)
            let id = String(prefix.dropLast("/files".count))
            if let container = service.containers.first(where: { $0.id == id }) {
                return .json(["path": service.openPathHint(for: container)])
            }
            return .json(["path": "\(service.filesBasePath)/containers/\(id)"])
        }
        if request.method == "DELETE", request.path.hasPrefix("/api/images/") {
            let id = String(request.path.dropFirst("/api/images/".count))
            return await mutate { try await service.removeImage(id: id) }
        }
        if request.method == "DELETE", request.path.hasPrefix("/api/volumes/") {
            let name = String(request.path.dropFirst("/api/volumes/".count))
            let force = request.query["force"] == "true"
            return await mutate { try await service.removeVolume(name: name, force: force) }
        }
        if request.method == "DELETE", request.path.hasPrefix("/api/networks/") {
            let name = String(request.path.dropFirst("/api/networks/".count))
            return await mutate { try await service.removeNetwork(name: name) }
        }
        if request.method == "POST", request.path.hasPrefix("/api/compose/"), request.path.hasSuffix("/start") {
            let prefix = request.path.dropFirst("/api/compose/".count)
            let name = String(prefix.dropLast("/start".count))
            let decoded = name.removingPercentEncoding ?? name
            return await mutate { try await service.startComposeStack(projectName: decoded) }
        }
        if request.method == "POST", request.path.hasPrefix("/api/compose/"), request.path.hasSuffix("/stop") {
            let prefix = request.path.dropFirst("/api/compose/".count)
            let name = String(prefix.dropLast("/stop".count))
            let decoded = name.removingPercentEncoding ?? name
            return await mutate { try await service.stopComposeStack(projectName: decoded) }
        }
        return .error("Not found", status: 404)
    }

    private func makeSnapshot() -> APISnapshot {
        APISnapshot(
            systemStatus: service.systemStatus,
            containers: service.containers,
            images: service.images,
            volumes: service.volumes,
            networks: service.networks,
            composeProjects: service.composeProjects,
            settings: service.settings,
            filesBasePath: service.filesBasePath,
            isInstalled: service.isInstalled,
            installPhase: service.installPhase.apiLabel,
            isInstallingToolkit: service.isInstallingToolkit,
            lastError: service.lastError
        )
    }

    private func containerID(from path: String, action: String) -> String {
        let prefix = "/api/containers/"
        let suffix = "/\(action)"
        return String(path.dropFirst(prefix.count).dropLast(suffix.count))
    }

    private func pullImage(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(PullImageBody.self, from: request.body)
            try await service.pullImage(body.reference)
            await service.refresh(all: true)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func runContainer(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(RunContainerBody.self, from: request.body)
            try await service.runQuick(
                image: body.image,
                ports: body.ports ?? [],
                detach: body.detach ?? true,
                remove: body.remove ?? false,
                command: body.command ?? []
            )
            await service.refresh(all: true)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func mutateSettings(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(AppSettings.self, from: request.body)
            try service.updateSettings(body)
            return .json(service.settings)
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func batchStart(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(APIBatchBody.self, from: request.body)
            try await service.batchStartContainers(ids: body.ids)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func batchStop(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(APIBatchBody.self, from: request.body)
            try await service.batchStopContainers(ids: body.ids)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func batchRemove(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(APIBatchBody.self, from: request.body)
            try await service.batchRemoveContainers(ids: body.ids, force: body.force ?? true)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func createVolume(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(APICreateVolumeBody.self, from: request.body)
            try await service.createVolume(name: body.name)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func createNetwork(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            let body = try JSONDecoder().decode(APICreateNetworkBody.self, from: request.body)
            try await service.createNetwork(name: body.name)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 400)
        }
    }

    private func mutate(_ work: () async throws -> Void) async -> HTTPResponse {
        do {
            try await work()
            await service.refresh(all: true)
            return .json(makeSnapshot())
        } catch {
            return .error(error.localizedDescription, status: 500)
        }
    }

    private func query<T: Encodable>(_ work: () async throws -> T) async -> HTTPResponse {
        do {
            return .json(try await work())
        } catch {
            return .error(error.localizedDescription, status: 500)
        }
    }
}

private struct PullImageBody: Codable {
    var reference: String
}

private struct RunContainerBody: Codable {
    var image: String
    var ports: [String]?
    var detach: Bool?
    var remove: Bool?
    var command: [String]?
}
