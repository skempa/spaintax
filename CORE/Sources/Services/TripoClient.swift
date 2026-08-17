import Foundation

/// Minimal async client for the Tripo3D v3 API.
///
/// Endpoint shapes mirror the official `@vastai/tripo-sdk` JavaScript
/// client: `Authorization: Bearer <key>`, `{code, data, message,
/// suggestion}` response envelope, task-based generation with polling.
final class TripoClient {

    enum TripoError: LocalizedError {
        case http(Int, String)
        case api(code: Int, message: String, suggestion: String?)
        case taskFailed(status: String)
        case timeout
        case badResponse

        var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                return "HTTP \(status): \(body)"
            case .api(_, let message, let suggestion):
                return suggestion.map { "\(message) — \($0)" } ?? message
            case .taskFailed(let status):
                return "Generation \(status)."
            case .timeout:
                return "Generation timed out."
            case .badResponse:
                return "Unexpected response from Tripo."
            }
        }
    }

    struct TaskOutput: Decodable {
        var modelUrl: String?
        var model: String?
        var pbrModel: String?
        var baseModel: String?
        var modelUrls: [String]?
        var image: String?
        var imageUrl: String?
        var images: [String]?
        var rigType: String?
        var recommendedRigType: String?
        var riggable: Bool?

        var primaryModelURL: String? {
            modelUrl ?? model ?? pbrModel ?? baseModel ?? modelUrls?.first
        }
        var primaryImageURL: String? {
            image ?? imageUrl ?? images?.first
        }
    }

    struct TripoTask: Decodable {
        var taskId: String?
        var status: String
        var progress: Int?
        var output: TaskOutput?

        var isTerminal: Bool {
            ["success", "failed", "cancelled", "banned", "expired"].contains(status)
        }
    }

    private struct Envelope<T: Decodable>: Decodable {
        var code: Int?
        var data: T?
        var message: String?
        var suggestion: String?
    }

    private struct TaskCreated: Decodable { var taskId: String? }
    private struct FileUploaded: Decodable { var fileToken: String? }

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(apiKey: String, baseURL: URL = URL(string: "https://openapi.tripo3d.ai/v3")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        self.session = URLSession(configuration: config)
    }

    // MARK: - Requests

    private func request<T: Decodable>(_ path: String,
                                       method: String = "GET",
                                       json: [String: Any]? = nil,
                                       multipart: (data: Data, filename: String)? = nil) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if let multipart {
            let boundary = "core-\(UUID().uuidString)"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(multipart.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(multipart.data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            req.httpBody = body
        } else if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TripoError.badResponse }

        let envelope = try? decoder.decode(Envelope<T>.self, from: data)
        if !(200..<300).contains(http.statusCode) {
            if let envelope, let message = envelope.message {
                throw TripoError.api(code: envelope.code ?? http.statusCode, message: message, suggestion: envelope.suggestion)
            }
            throw TripoError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        guard let envelope else { throw TripoError.badResponse }
        if let code = envelope.code, code != 0, envelope.data == nil {
            throw TripoError.api(code: code, message: envelope.message ?? "Tripo error \(code)", suggestion: envelope.suggestion)
        }
        guard let payload = envelope.data else { throw TripoError.badResponse }
        return payload
    }

    // MARK: - API surface

    /// POST /v3/files → file_token
    func uploadFile(_ data: Data, filename: String) async throws -> String {
        let result: FileUploaded = try await request("files", method: "POST", multipart: (data, filename))
        guard let token = result.fileToken else { throw TripoError.badResponse }
        return token
    }

    /// Creates any task-producing job and returns its task_id.
    func createTask(_ path: String, body: [String: Any]) async throws -> String {
        let result: TaskCreated = try await request(path, method: "POST", json: body)
        guard let id = result.taskId else { throw TripoError.badResponse }
        return id
    }

    /// GET /v3/tasks/{id}
    func getTask(_ id: String) async throws -> TripoTask {
        try await request("tasks/\(id)")
    }

    /// Polls until the task settles; throws on non-success terminal states.
    func waitForTask(_ id: String,
                     timeout: TimeInterval = 600,
                     onProgress: ((TripoTask) -> Void)? = nil) async throws -> TripoTask {
        let started = Date()
        while true {
            try Task.checkCancellation()
            let task = try await getTask(id)
            onProgress?(task)
            if task.isTerminal {
                guard task.status == "success" else { throw TripoError.taskFailed(status: task.status) }
                return task
            }
            if Date().timeIntervalSince(started) > timeout { throw TripoError.timeout }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    /// Downloads a result artifact (model/image URL from a task output).
    func download(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw TripoError.badResponse }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TripoError.badResponse
        }
        return data
    }

    /// GET /v3/account/balance — used as a cheap key-validity check.
    func checkKey() async throws {
        struct Balance: Decodable { var balance: Double? }
        let _: Balance = try await request("account/balance")
    }
}
