import Foundation
import UIKit

/// JSON persistence for the game state and drawing images.
///
/// Everything lives in the App Group container so the DeviceActivity
/// monitor extension shares the same storage domain. The creature is
/// permanent: `save()` is called after every meaningful mutation.
final class GameStore {
    static let shared = GameStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// App Group container when available, Documents otherwise (simulator
    /// without entitlements).
    var directory: URL {
        if let group = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: DeviceActivityScreenTimeProvider.appGroupID
        ) {
            return group
        }
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var stateURL: URL { directory.appendingPathComponent("gamestate.json") }

    func load() -> GameState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? decoder.decode(GameState.self, from: data) else {
            return GameState()
        }
        return state
    }

    func save(_ state: GameState) {
        guard let data = try? encoder.encode(state) else { return }
        // Atomic write: a crash mid-save must never corrupt the creature.
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Images

    @discardableResult
    func saveImage(_ image: UIImage, named name: String) -> Bool {
        guard let data = image.pngData() else { return false }
        let url = directory.appendingPathComponent(name)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    func loadImage(named name: String) -> UIImage? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
