import Foundation

struct ZCodeDiscoveredCredentials {
    let goKey: String?
    let glmKey: String?
    let goProviderIDs: Set<String>
}

struct ZCodeCredentialReader {
    let zcodeHome: URL
    private let fallbackAuthOverride: URL?

    init(zcodeHome: URL, fallbackAuthURL: URL? = nil) {
        self.zcodeHome = zcodeHome
        self.fallbackAuthOverride = fallbackAuthURL
    }

    var configURL: URL {
        zcodeHome.appendingPathComponent("v2/config.json")
    }

    var fallbackAuthURL: URL {
        if let fallbackAuthOverride {
            return fallbackAuthOverride
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    func discover() -> ZCodeDiscoveredCredentials {
        let root = readObject(from: configURL) ?? [:]
        let providers = providerMap(from: root)

        var goProviderIDs = Set<String>()
        var baseURLGoKey: String?
        var namedGoKey: String?
        var glmKey: String?

        for providerID in providers.keys.sorted() {
            guard let provider = providers[providerID] as? [String: Any] else { continue }
            let options = provider["options"] as? [String: Any] ?? [:]
            let apiKey = firstNonEmptyString([
                options["apiKey"],
                provider["apiKey"]
            ])
            let baseURL = firstNonEmptyString([
                options["baseURL"],
                options["baseUrl"],
                provider["baseURL"],
                provider["baseUrl"]
            ])
            let name = firstNonEmptyString([
                provider["name"],
                options["name"]
            ])

            if providerID == "builtin:bigmodel-coding-plan" {
                glmKey = apiKey ?? glmKey
            }

            let matchesBaseURL = baseURL.map(isExactGoBaseURL) ?? false
            let matchesExactName = name.map(isExactOpenCodeGoName) ?? false
            let matchesExactID = isExactOpenCodeGoName(providerID)
            if matchesBaseURL || matchesExactName || matchesExactID {
                goProviderIDs.insert(providerID)
                if matchesBaseURL {
                    baseURLGoKey = baseURLGoKey ?? apiKey
                } else {
                    namedGoKey = namedGoKey ?? apiKey
                }
            }
        }

        let fallbackGoKey: String?
        if let baseURLGoKey, !baseURLGoKey.isEmpty {
            fallbackGoKey = baseURLGoKey
        } else if let namedGoKey, !namedGoKey.isEmpty {
            fallbackGoKey = namedGoKey
        } else {
            fallbackGoKey = readFallbackGoKey()
        }

        return ZCodeDiscoveredCredentials(
            goKey: fallbackGoKey,
            glmKey: glmKey,
            goProviderIDs: goProviderIDs
        )
    }

    func resolver() -> ZCodeProviderResolver {
        ZCodeProviderResolver(goProviderIDs: discover().goProviderIDs)
    }

    private func readFallbackGoKey() -> String? {
        guard
            let root = readObject(from: fallbackAuthURL),
            let provider = root["opencode-go"] as? [String: Any]
        else {
            return nil
        }
        return firstNonEmptyString([provider["key"]])
    }
}

struct ZCodeProviderResolver {
    let goProviderIDs: Set<String>

    func provider(for providerID: String) -> ZCodeProvider {
        if providerID == "builtin:bigmodel-coding-plan" {
            return .glm
        }
        if goProviderIDs.contains(providerID) || isExactOpenCodeGoName(providerID) {
            return .go
        }
        return .unknown
    }
}

func readObject(from url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func providerMap(from root: [String: Any]) -> [String: Any] {
    if let providers = root["provider"] as? [String: Any] {
        return providers
    }
    if let providers = root["providers"] as? [String: Any] {
        return providers
    }
    return [:]
}

func firstNonEmptyString(_ values: [Any?]) -> String? {
    for value in values {
        guard let string = value as? String else { continue }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

func normalizedProviderName(_ value: String) -> String {
    String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

func isExactOpenCodeGoName(_ value: String) -> Bool {
    normalizedProviderName(value) == "opencodego"
}

func isExactGoBaseURL(_ value: String) -> Bool {
    guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return false
    }
    guard url.host?.lowercased() == "opencode.ai" else { return false }
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return "/\(path)" == "/zen/go/v1"
}
