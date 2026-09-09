import Foundation

struct ZCodeTokenStatsResult {
    let todayTokens: Int?
    let cumulativeTokens: Int?
    let provider: ZCodeProvider?
    let statsReady: Bool
    let invalidRecordCount: Int
    let error: String?
}

final class ZCodeTokenStatsStore {
    private static let cacheVersion = 2
    private static let defaultChunkSize = 2 * 1024 * 1024

    private struct LatestRecord: Codable {
        var completedAtMilliseconds: Int64
        var providerID: String
    }

    private struct FileState: Codable {
        var identity: String?
        var observedSize: Int64
        var observedModificationMilliseconds: Int64?
        var offset: Int64
        var caughtUpAtEOF: Bool
        var scanned: Bool
        var totalTokens: Int64
        var dailyTokens: [String: Int64]
        var requestIDs: Set<String>
        var validRecordCount: Int
        var invalidRecordCount: Int
        var latest: LatestRecord?

        static var empty: FileState {
            FileState(
                identity: nil,
                observedSize: 0,
                observedModificationMilliseconds: nil,
                offset: 0,
                caughtUpAtEOF: false,
                scanned: false,
                totalTokens: 0,
                dailyTokens: [:],
                requestIDs: [],
                validRecordCount: 0,
                invalidRecordCount: 0,
                latest: nil
            )
        }
    }

    private struct Cache: Codable {
        var version: Int
        var files: [String: FileState]
        var cursorPath: String?

        static var empty: Cache {
            Cache(version: ZCodeTokenStatsStore.cacheVersion, files: [:], cursorPath: nil)
        }
    }

    private struct PendingLine {
        var data: Data
        var nextReadOffset: Int64
    }

    private struct RolloutScan {
        var files: [URL]
        var readable: Bool
    }

    private struct ParsedRequest {
        var tokenCount: Int64
        var day: String
        var completedAtMilliseconds: Int64
        var providerID: String
        var requestID: String?
    }

    private let zcodeHome: URL
    private let cacheFile: URL
    private var cache: Cache
    // Partial lines stay in memory only. The persisted offset remains at the last complete line.
    private var pendingLines: [String: PendingLine] = [:]

#if ZCODE_TESTING
    static var testingCancelAfterCompleteLines: Int?
#endif

    init(zcodeHome: URL, cacheFile: URL) {
        self.zcodeHome = zcodeHome
        self.cacheFile = cacheFile
        self.cache = Self.loadCache(from: cacheFile)
    }

    func refresh(
        maxBytes: Int = ZCodeTokenStatsStore.defaultChunkSize,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ZCodeTokenStatsResult {
        let rollout = rolloutFiles()
        guard rollout.readable else {
            return ZCodeTokenStatsResult(
                todayTokens: nil,
                cumulativeTokens: nil,
                provider: nil,
                statsReady: true,
                invalidRecordCount: 0,
                error: "rollout directory unreadable"
            )
        }

        let files = rollout.files
        let paths = Set(files.map(\.path))
        cache.files = cache.files.filter { paths.contains($0.key) }
        pendingLines = pendingLines.filter { paths.contains($0.key) }

        if files.isEmpty {
            cache.cursorPath = nil
        } else {
            scan(
                files: files,
                maxBytes: max(0, maxBytes),
                calendar: calendar
            )
        }

        persistCache()
        return aggregate(
            files: files,
            now: now,
            calendar: calendar
        )
    }

    private func scan(
        files: [URL],
        maxBytes: Int,
        calendar: Calendar
    ) {
        let paths = files.map(\.path)
        let start: Int
        if let cursor = cache.cursorPath, let index = paths.firstIndex(of: cursor) {
            start = index
        } else {
            start = 0
        }

        var remaining = maxBytes
        var visited = 0
        var cursorWasBlocked = false

        while visited < files.count {
            if Task.isCancelled {
                cursorWasBlocked = true
                break
            }

            let index = (start + visited) % files.count
            let url = files[index]
            let path = url.path
            let initialSize = fileSize(url)
            var state = cache.files[path] ?? .empty

            if shouldReset(state: state, url: url, currentSize: initialSize) {
                state = .empty
                pendingLines.removeValue(forKey: path)
            }

            let grewSinceLastScan = initialSize > state.observedSize
            state.scanned = true
            state.identity = fileIdentity(url)
            if grewSinceLastScan {
                state.caughtUpAtEOF = false
            }

            if state.caughtUpAtEOF,
               !grewSinceLastScan,
               pendingLines[path] == nil {
                state.observedSize = initialSize
                state.observedModificationMilliseconds = modificationMilliseconds(url)
                cache.files[path] = state
                cache.cursorPath = paths[(index + 1) % files.count]
                visited += 1
                continue
            }

            let pending = pendingLines[path]
            let readOffset = pending?.nextReadOffset ?? state.offset
            if readOffset > initialSize {
                pendingLines.removeValue(forKey: path)
                state.caughtUpAtEOF = false
                cache.files[path] = state
                cache.cursorPath = path
                cursorWasBlocked = true
                break
            }

            if readOffset < initialSize {
                guard remaining > 0 else {
                    cache.files[path] = state
                    cache.cursorPath = path
                    cursorWasBlocked = true
                    break
                }

                let allowance = min(remaining, Int(initialSize - readOffset))
                do {
                    let data = try readChunk(url: url, offset: readOffset, length: allowance)
                    guard !data.isEmpty else {
                        cache.files[path] = state
                        cache.cursorPath = path
                        cursorWasBlocked = true
                        break
                    }
                    remaining -= data.count

                    let priorData = pending?.data ?? Data()
                    var combined = Data()
                    combined.reserveCapacity(priorData.count + data.count)
                    combined.append(priorData)
                    combined.append(data)

                    let completeByteCount = completeLineByteCount(in: combined)
                    var committedByteCount = 0
                    var cancelledDuringParse = false
                    if completeByteCount > 0 {
                        let completeData = combined.prefix(completeByteCount)
                        var lineStart = completeData.startIndex
                        for newlineIndex in completeData.indices where completeData[newlineIndex] == 10 {
                            guard !Task.isCancelled else {
                                cancelledDuringParse = true
                                cursorWasBlocked = true
                                break
                            }
                            let lineData = Data(completeData[lineStart..<newlineIndex])
                            switch parseRequest(lineData, calendar: calendar) {
                            case .valid(let request):
                                apply(request, to: &state)
                            case .invalid:
                                state.invalidRecordCount += 1
                            case .empty:
                                break
                            }
#if ZCODE_TESTING
                            if let remainingLines = Self.testingCancelAfterCompleteLines {
                                if remainingLines <= 1 {
                                    Self.testingCancelAfterCompleteLines = nil
                                    withUnsafeCurrentTask { $0?.cancel() }
                                } else {
                                    Self.testingCancelAfterCompleteLines = remainingLines - 1
                                }
                            }
#endif
                            // Commit one complete line only after its parse has returned.
                            committedByteCount += completeData.distance(from: lineStart, to: newlineIndex) + 1
                            lineStart = completeData.index(after: newlineIndex)
                        }
                    }

                    if committedByteCount > 0 {
                        state.offset += Int64(committedByteCount)
                    }

                    if cancelledDuringParse || Task.isCancelled {
                        // Do not retain a complete-but-uncommitted line at EOF: the next
                        // refresh must reread it from the persisted complete-line offset.
                        pendingLines.removeValue(forKey: path)
                        state.caughtUpAtEOF = false
                        state.observedSize = fileSize(url)
                        state.observedModificationMilliseconds = modificationMilliseconds(url)
                        cache.files[path] = state
                        cache.cursorPath = path
                        cursorWasBlocked = true
                        break
                    }

                    let uncommitted = combined.dropFirst(committedByteCount)
                    if !uncommitted.isEmpty {
                        pendingLines[path] = PendingLine(
                            data: Data(uncommitted),
                            nextReadOffset: readOffset + Int64(data.count)
                        )
                    } else {
                        pendingLines.removeValue(forKey: path)
                    }
                } catch {
                    cursorWasBlocked = true
                }
            }

            let refreshedSize = fileSize(url)
            state.observedSize = refreshedSize
            state.observedModificationMilliseconds = modificationMilliseconds(url)
            let pendingAfterRead = pendingLines[path]
            let nextReadOffset = pendingAfterRead?.nextReadOffset ?? state.offset
            let pendingHasCompleteLine = pendingAfterRead?.data.contains(10) == true
            state.caughtUpAtEOF = nextReadOffset >= refreshedSize && !pendingHasCompleteLine
            if state.caughtUpAtEOF {
                // The partial tail is represented by offset + caughtUpAtEOF on disk;
                // reread it after the next append instead of retaining its content.
                pendingLines.removeValue(forKey: path)
            }
            cache.files[path] = state

            if cursorWasBlocked || nextReadOffset < refreshedSize {
                cache.cursorPath = path
                break
            }

            cache.cursorPath = paths[(index + 1) % files.count]
            visited += 1
        }

        if !cursorWasBlocked, visited >= files.count {
            cache.cursorPath = paths[start]
        }
    }

    private enum ParseResult {
        case empty
        case invalid
        case valid(ParsedRequest)
    }

    private func parseRequest(_ data: Data, calendar: Calendar) -> ParseResult {
        guard !data.isEmpty else { return .empty }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let completedAt = zcodeDate(object["completedAt"]),
            let model = object["model"] as? [String: Any],
            let providerID = firstNonEmptyString([model["providerId"]]),
            let response = object["response"] as? [String: Any],
            let responseUsage = response["usage"] as? [String: Any],
            let tokenCount = tokenCount(from: responseUsage)
        else {
            return .invalid
        }

        let milliseconds = Int64((completedAt.timeIntervalSince1970 * 1_000).rounded(.down))
        return .valid(
            ParsedRequest(
                tokenCount: tokenCount,
                day: zcodeDayKey(for: completedAt, calendar: calendar),
                completedAtMilliseconds: milliseconds,
                providerID: providerID,
                requestID: firstNonEmptyString([object["requestId"]])
            )
        )
    }

    private func tokenCount(from usage: [String: Any]) -> Int64? {
        if let total = zcodeNonNegativeInteger(usage["totalTokens"]) {
            return total
        }
        guard
            let input = zcodeNonNegativeInteger(usage["inputTokens"]),
            let output = zcodeNonNegativeInteger(usage["outputTokens"])
        else {
            return nil
        }
        let (sum, overflow) = input.addingReportingOverflow(output)
        return overflow ? nil : sum
    }

    private func apply(_ request: ParsedRequest, to state: inout FileState) {
        if let requestID = request.requestID, state.requestIDs.contains(requestID) {
            return
        }

        let (newTotal, totalOverflow) = state.totalTokens.addingReportingOverflow(request.tokenCount)
        guard !totalOverflow else { return }
        let existingDay = state.dailyTokens[request.day] ?? 0
        let (newDay, dayOverflow) = existingDay.addingReportingOverflow(request.tokenCount)
        guard !dayOverflow else { return }

        state.totalTokens = newTotal
        state.dailyTokens[request.day] = newDay
        state.validRecordCount += 1
        if let requestID = request.requestID {
            state.requestIDs.insert(requestID)
        }
        if state.latest?.completedAtMilliseconds ?? Int64.min <= request.completedAtMilliseconds {
            state.latest = LatestRecord(
                completedAtMilliseconds: request.completedAtMilliseconds,
                providerID: request.providerID
            )
        }
    }

    private func aggregate(
        files: [URL],
        now: Date,
        calendar: Calendar
    ) -> ZCodeTokenStatsResult {
        var total: Int64 = 0
        var daily: [String: Int64] = [:]
        var validRecordCount = 0
        var invalidRecordCount = 0
        var newest: LatestRecord?

        for state in cache.files.values {
            let (newTotal, totalOverflow) = total.addingReportingOverflow(state.totalTokens)
            if totalOverflow {
                return ZCodeTokenStatsResult(
                    todayTokens: nil,
                    cumulativeTokens: nil,
                    provider: nil,
                    statsReady: isReady(files: files),
                    invalidRecordCount: invalidRecordCount + 1,
                    error: nil
                )
            }
            total = newTotal
            validRecordCount += state.validRecordCount
            invalidRecordCount += state.invalidRecordCount
            for (day, value) in state.dailyTokens {
                let existing = daily[day] ?? 0
                let (combined, overflow) = existing.addingReportingOverflow(value)
                if overflow {
                    return ZCodeTokenStatsResult(
                        todayTokens: nil,
                        cumulativeTokens: nil,
                        provider: nil,
                        statsReady: isReady(files: files),
                        invalidRecordCount: invalidRecordCount + 1,
                        error: nil
                    )
                }
                daily[day] = combined
            }
            if let latest = state.latest,
               newest?.completedAtMilliseconds ?? Int64.min <= latest.completedAtMilliseconds {
                newest = latest
            }
        }

        let resolver = ZCodeCredentialReader(zcodeHome: zcodeHome).resolver()
        let provider = newest.map { resolver.provider(for: $0.providerID) }
        let today = zcodeDayKey(for: now, calendar: calendar)
        let ready = isReady(files: files)
        let cumulativeTokens: Int?
        let todayTokens: Int?
        if validRecordCount > 0 {
            cumulativeTokens = Int(exactly: total)
            todayTokens = Int(exactly: daily[today] ?? 0)
        } else if ready && invalidRecordCount == 0 {
            cumulativeTokens = 0
            todayTokens = 0
        } else {
            cumulativeTokens = nil
            todayTokens = nil
        }

        return ZCodeTokenStatsResult(
            todayTokens: todayTokens,
            cumulativeTokens: cumulativeTokens,
            provider: provider,
            statsReady: ready,
            invalidRecordCount: invalidRecordCount,
            error: nil
        )
    }

    private func isReady(files: [URL]) -> Bool {
        for url in files {
            guard let state = cache.files[url.path], state.scanned else { return false }
            let size = fileSize(url)
            if shouldReset(state: state, url: url, currentSize: size) { return false }
            if size > state.observedSize { return false }
            if state.caughtUpAtEOF { continue }
            if state.offset < size { return false }
        }
        return true
    }

    private func rolloutFiles() -> RolloutScan {
        let root = zcodeHome.appendingPathComponent("cli/rollout")
        let manager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return RolloutScan(files: [], readable: false)
        }
        guard (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) != nil else {
            return RolloutScan(files: [], readable: false)
        }
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return RolloutScan(files: [], readable: false)
        }

        let files: [URL] = enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("model-io-sess_") else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url : nil
        }.sorted { $0.path < $1.path }
        return RolloutScan(files: files, readable: true)
    }

    private func shouldReset(state: FileState, url: URL, currentSize: Int64) -> Bool {
        guard state.scanned else { return false }
        if currentSize < state.offset || currentSize < state.observedSize { return true }
        if let oldIdentity = state.identity, let newIdentity = fileIdentity(url), oldIdentity != newIdentity {
            return true
        }
        if currentSize == state.observedSize,
           let oldModification = state.observedModificationMilliseconds,
           let newModification = modificationMilliseconds(url),
           oldModification != newModification {
            return true
        }
        return false
    }

    private func readChunk(url: URL, offset: Int64, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return handle.readData(ofLength: length)
    }

    private func completeLineByteCount(in data: Data) -> Int {
        guard let lastNewline = data.lastIndex(of: 10) else { return 0 }
        return data.distance(from: data.startIndex, to: lastNewline) + 1
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return max(0, size.int64Value)
    }

    private func fileIdentity(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let device = (attributes[.systemNumber] as? NSNumber)?.stringValue
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.stringValue
        if let device, let inode {
            return "\(device):\(inode)"
        }
        return nil
    }

    private func modificationMilliseconds(_ url: URL) -> Int64? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let date = attributes[.modificationDate] as? Date,
            date.timeIntervalSince1970.isFinite
        else {
            return nil
        }
        return Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private func persistCache() {
        guard let data = try? JSONEncoder.zcodeEncoder.encode(cache) else { return }
        try? ZCodeAtomicFile.write(data, to: cacheFile)
    }

    private static func loadCache(from url: URL) -> Cache {
        guard
            let data = try? Data(contentsOf: url),
            let cache = try? JSONDecoder().decode(Cache.self, from: data),
            cache.version == cacheVersion
        else {
            return .empty
        }
        return cache
    }
}

private func zcodeDate(_ value: Any?) -> Date? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return fractional.date(from: text) ?? plain.date(from: text)
}

private func zcodeDayKey(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
}

enum ZCodeAtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }
}

extension JSONEncoder {
    static var zcodeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
