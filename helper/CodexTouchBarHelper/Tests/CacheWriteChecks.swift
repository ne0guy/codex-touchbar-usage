import Foundation

@main
struct CacheCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cache.json")
        try writeJSONObject(["writer": -1, "values": Array(repeating: -1, count: 100)], to: url)
        DispatchQueue.concurrentPerform(iterations: 100) { writer in
            do {
                try writeJSONObject(["writer": writer, "values": Array(repeating: writer, count: 100)], to: url)
                let object = try readJSONObject(from: url)
                guard let id = object["writer"] as? Int, let values = object["values"] as? [Int],
                      values.count == 100, values.allSatisfy({ $0 == id }) else { fatalError("torn cache") }
            } catch { fatalError("cache write failed: \(error)") }
        }
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["cache.json"] else {
            fatalError("temporary files leaked")
        }
        print("Cache creation and 100 concurrent atomic writes: PASS")
    }
}
