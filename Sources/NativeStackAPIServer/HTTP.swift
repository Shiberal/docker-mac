import Foundation

public struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data
}

public struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data

    public static func json<T: Encodable>(_ value: T, status: Int = 200, encoder: JSONEncoder = .api) -> HTTPResponse {
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    public static func error(_ message: String, status: Int = 400) -> HTTPResponse {
        json(APIErrorResponse(error: message), status: status)
    }

    public static func noContent() -> HTTPResponse {
        HTTPResponse(status: 204, headers: [:], body: Data())
    }

    public func serialize() -> Data {
        var headerLines = ["HTTP/1.1 \(status) \(HTTPResponse.statusText(status))"]
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        allHeaders["Access-Control-Allow-Origin"] = "*"
        allHeaders["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
        allHeaders["Access-Control-Allow-Headers"] = "Content-Type"
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            headerLines.append("\(key): \(value)")
        }
        var data = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        data.append(body)
        return data
    }

    private static func statusText(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 500: "Internal Server Error"
        default: "OK"
        }
    }
}

struct APIErrorResponse: Codable, Sendable {
    let error: String
}

extension JSONEncoder {
    public static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

enum HTTPParser {
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard let head = parts.first else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else { return nil }

        let method = String(requestParts[0]).uppercased()
        let target = String(requestParts[1])
        let urlParts = target.split(separator: "?", maxSplits: 1)
        let path = String(urlParts[0])
        var query: [String: String] = [:]
        if urlParts.count == 2 {
            for pair in urlParts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard let key = kv.first else { continue }
                let value = kv.count == 2 ? String(kv[1]) : ""
                query[String(key)] = value.removingPercentEncoding ?? value
            }
        }

        let bodyData: Data
        if parts.count > 1 {
            bodyData = Data(parts[1].utf8)
        } else {
            bodyData = Data()
        }

        return HTTPRequest(method: method, path: path, query: query, body: bodyData)
    }
}
