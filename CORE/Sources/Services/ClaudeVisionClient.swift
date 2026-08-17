import Foundation
import UIKit

/// Minimal client for the Claude Messages API, used for one thing: looking
/// at the player's drawing and putting into words what they drew, so they
/// can confirm or edit it before the creature is generated.
///
/// Raw URLSession like `TripoClient` — no SDK dependency.
final class ClaudeVisionClient {

    enum ClaudeError: LocalizedError {
        case http(Int, String)
        case api(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .http(let status, let body): return "HTTP \(status): \(body)"
            case .api(let message):           return message
            case .badResponse:                return "Unexpected response from Claude."
            }
        }
    }

    static let model = "claude-opus-4-8"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    /// The instructions that shape the description. One sentence, in the
    /// owner's voice, only what is visibly drawn — the player will edit it.
    static let systemPrompt = """
    You are looking at a freehand drawing of an imaginary creature, made with a finger in a phone app, often by a child. \
    Write ONE sentence of at most 25 words describing the creature the way its owner would say it out loud: \
    what kind of thing it is, its colours, its body shape, and one or two standout features or its expression. \
    Start with "A" or "An". Describe only what is visibly drawn — never guess at things that aren't there. \
    No preamble, no quotation marks, and do not mention that it is a drawing or sketch. \
    Example: An orange cat with big pointed ears and a jagged toothy grin.
    """

    /// Returns a short, editable creature description.
    func describeDrawing(_ image: UIImage) async throws -> String {
        guard let png = image.downscaled(maxSide: 1024).pngData() else {
            throw ClaudeError.badResponse
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "system": Self.systemPrompt,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]],
                    ["type": "text", "text": "Describe this creature."]
                ]
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(http.statusCode) else {
            if let error = json?["error"] as? [String: Any], let message = error["message"] as? String {
                throw ClaudeError.api(message)
            }
            throw ClaudeError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }

        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            throw ClaudeError.badResponse
        }
        return Self.clean(text)
    }

    /// Trims whitespace and any wrapping quotes the model might add.
    private static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = s.first, "\"'“”‘’".contains(first) { s.removeFirst() }
        while let last = s.last, "\"'“”‘’".contains(last) { s.removeLast() }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension UIImage {
    /// Keeps upload payloads small; the drawing has no fine detail to lose.
    func downscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
