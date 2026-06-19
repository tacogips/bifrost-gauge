import AppKit
import Foundation

enum BudgetResetWindow: String, CaseIterable {
    case minute = "1m"
    case hour = "1h"
    case day = "1d"
    case week = "1w"
    case month = "1M"
    case year = "1Y"

    var title: String {
        switch self {
        case .minute: return "Every Minute"
        case .hour: return "Hourly"
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Yearly"
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable {
    case percent
    case spendAmount
    case pie
    case percentAndSpendAmount
    case pieAndPercent
    case pieAndSpendAmount
    case pieAndPercentAndSpendAmount

    var title: String {
        switch self {
        case .percent: return "Percent"
        case .spendAmount: return "Spend Amount"
        case .pie: return "Pie"
        case .percentAndSpendAmount: return "Percent + Spend Amount"
        case .pieAndPercent: return "Pie + Percent"
        case .pieAndSpendAmount: return "Pie + Spend Amount"
        case .pieAndPercentAndSpendAmount: return "Pie + Percent + Spend Amount"
        }
    }

    var showsPie: Bool {
        switch self {
        case .pie, .pieAndPercent, .pieAndSpendAmount, .pieAndPercentAndSpendAmount:
            return true
        case .percent, .spendAmount, .percentAndSpendAmount:
            return false
        }
    }

    var showsPercent: Bool {
        switch self {
        case .percent, .percentAndSpendAmount, .pieAndPercent, .pieAndPercentAndSpendAmount:
            return true
        case .spendAmount, .pie, .pieAndSpendAmount:
            return false
        }
    }

    var showsSpendAmount: Bool {
        switch self {
        case .spendAmount, .percentAndSpendAmount, .pieAndSpendAmount, .pieAndPercentAndSpendAmount:
            return true
        case .percent, .pie, .pieAndPercent:
            return false
        }
    }
}

struct AppMetadata {
    static var versionDescription: String {
        let version = bundleValue(for: "CFBundleShortVersionString") ?? "development"
        guard let build = bundleValue(for: "CFBundleVersion"), build != version else {
            return version
        }
        return "\(version) (\(build))"
    }

    private static func bundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AppConfig {
    static let defaultRefreshSeconds: TimeInterval = 10
    static let minimumRefreshSeconds: TimeInterval = 10

    var baseURL: URL
    var virtualKeyID: String
    var resetDuration: String?
    var refreshSeconds: TimeInterval
    var adminToken: String?

    static func load() -> AppConfig {
        let env = ProcessInfo.processInfo.environment
        var config = AppConfig(
            baseURL: URL(string: env["BIFROST_BASE_URL"] ?? "http://127.0.0.1:18080")!,
            virtualKeyID: env["BIFROST_VIRTUAL_KEY_ID"] ?? "vk-personal",
            resetDuration: emptyToNil(env["BIFROST_BUDGET_RESET_DURATION"]),
            refreshSeconds: max(
                Self.minimumRefreshSeconds,
                TimeInterval(env["BIFROST_REFRESH_SECONDS"] ?? "") ?? defaultRefreshSeconds
            ),
            adminToken: emptyToNil(env["BIFROST_ADMIN_TOKEN"])
        )

        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let key = args.removeFirst()
            guard !args.isEmpty else { break }
            let value = args.removeFirst()
            switch key {
            case "--base-url":
                if let url = URL(string: value) { config.baseURL = url }
            case "--vk-id":
                config.virtualKeyID = value
            case "--reset-duration":
                config.resetDuration = value
            case "--refresh-seconds":
                config.refreshSeconds = max(Self.minimumRefreshSeconds, TimeInterval(value) ?? config.refreshSeconds)
            case "--admin-token":
                config.adminToken = value
            default:
                continue
            }
        }
        return config
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

final class AppSettings {
    static let inactiveBudgetLimit = 1_000_000_000.0
    static func disabledBudgetLimitKey(virtualKeyID: String, budgetKey: String) -> String {
        "virtual-key:\(virtualKeyID):\(budgetKey)"
    }

    private let initial: AppConfig
    private let configURL: URL
    private var state: ConfigFileState

    init(initial: AppConfig) {
        self.initial = initial
        self.configURL = Self.defaultConfigURL()
        self.state = Self.loadState(from: configURL)
        applyDefaults()
        persist()
    }

    var baseURL: URL {
        get { URL(string: state.baseURL ?? initial.baseURL.absoluteString) ?? initial.baseURL }
        set {
            state.baseURL = newValue.absoluteString
            persist()
        }
    }

    var virtualKeyID: String {
        get { stringOrInitial(state.virtualKeyID, initial.virtualKeyID) }
        set {
            state.virtualKeyID = nonEmpty(newValue)
            persist()
        }
    }

    var resetDuration: String? {
        get { stringOrInitial(state.resetDuration, initial.resetDuration) }
        set {
            state.resetDuration = nonEmpty(newValue)
            persist()
        }
    }

    var refreshSeconds: TimeInterval {
        get {
            let value = state.refreshSeconds ?? 0
            return value > 0 ? max(AppConfig.minimumRefreshSeconds, value) : initial.refreshSeconds
        }
        set {
            state.refreshSeconds = max(AppConfig.minimumRefreshSeconds, newValue)
            persist()
        }
    }

    var adminToken: String? {
        get { stringOrInitial(state.adminToken, initial.adminToken) }
        set {
            state.adminToken = nonEmpty(newValue)
            persist()
        }
    }

    var defaultRaiseAmount: Double {
        get {
            let value = state.defaultRaiseAmount ?? 0
            return value > 0 ? value : 5.0
        }
        set {
            state.defaultRaiseAmount = max(0.01, newValue)
            persist()
        }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { MenuBarDisplayMode(rawValue: state.menuBarDisplayMode ?? "") ?? .pieAndPercent }
        set {
            state.menuBarDisplayMode = newValue.rawValue
            persist()
        }
    }

    func disabledBudgetLimit(forVirtualKeyID virtualKeyID: String, budgetKey: String) -> Double? {
        let key = Self.disabledBudgetLimitKey(virtualKeyID: virtualKeyID, budgetKey: budgetKey)
        return state.disabledBudgetLimits?[key]
    }

    func setDisabledBudgetLimit(_ limit: Double?, forVirtualKeyID virtualKeyID: String, budgetKey: String) {
        let key = Self.disabledBudgetLimitKey(virtualKeyID: virtualKeyID, budgetKey: budgetKey)
        if state.disabledBudgetLimits == nil {
            state.disabledBudgetLimits = [:]
        }
        state.disabledBudgetLimits?[key] = limit
        if state.disabledBudgetLimits?.isEmpty == true {
            state.disabledBudgetLimits = nil
        }
        persist()
    }

    func currentConfig() -> AppConfig {
        AppConfig(
            baseURL: baseURL,
            virtualKeyID: virtualKeyID,
            resetDuration: resetDuration,
            refreshSeconds: refreshSeconds,
            adminToken: adminToken
        )
    }

    private func stringOrInitial(_ saved: String?, _ initialValue: String) -> String {
        nonEmpty(saved) ?? initialValue
    }

    private func stringOrInitial(_ saved: String?, _ initialValue: String?) -> String? {
        nonEmpty(saved) ?? initialValue
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("bifrost-gauge", isDirectory: true)
            .appendingPathComponent("bifrost-gauge-config.json")
    }

    private static func loadState(from url: URL) -> ConfigFileState {
        guard let data = try? Data(contentsOf: url) else {
            return ConfigFileState()
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode(ConfigFileState.self, from: data)) ?? ConfigFileState()
    }

    private func persist() {
        do {
            let directory = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: configURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Failed to write \(configURL.path): \(error.localizedDescription)\n".utf8))
        }
    }

    private func applyDefaults() {
        state.baseURL = state.baseURL ?? initial.baseURL.absoluteString
        state.virtualKeyID = state.virtualKeyID ?? initial.virtualKeyID
        state.resetDuration = state.resetDuration ?? initial.resetDuration
        state.refreshSeconds = state.refreshSeconds ?? initial.refreshSeconds
        state.adminToken = state.adminToken ?? initial.adminToken
        state.defaultRaiseAmount = state.defaultRaiseAmount ?? 5.0
        state.menuBarDisplayMode = state.menuBarDisplayMode ?? MenuBarDisplayMode.pieAndPercent.rawValue
    }
}

struct ConfigFileState: Codable {
    var baseURL: String?
    var virtualKeyID: String?
    var resetDuration: String?
    var refreshSeconds: Double?
    var adminToken: String?
    var defaultRaiseAmount: Double?
    var menuBarDisplayMode: String?
    var disabledBudgetLimits: [String: Double]?

    var isEmpty: Bool {
        baseURL == nil &&
            virtualKeyID == nil &&
            resetDuration == nil &&
            refreshSeconds == nil &&
            adminToken == nil &&
            defaultRaiseAmount == nil &&
            menuBarDisplayMode == nil &&
            disabledBudgetLimits == nil
    }
}

struct VirtualKeyResponse: Decodable {
    let virtualKey: VirtualKey

    enum CodingKeys: String, CodingKey {
        case virtualKey = "virtual_key"
    }
}

struct VirtualKeysResponse: Decodable {
    let virtualKeys: [VirtualKey]

    enum CodingKeys: String, CodingKey {
        case virtualKeys = "virtual_keys"
        case camelVirtualKeys = "virtualKeys"
        case data
    }

    init(from decoder: Decoder) throws {
        if let virtualKeys = try? [VirtualKey](from: decoder) {
            self.virtualKeys = virtualKeys
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let virtualKeys = try container.decodeIfPresent([VirtualKey].self, forKey: .virtualKeys) {
            self.virtualKeys = virtualKeys
        } else if let virtualKeys = try container.decodeIfPresent([VirtualKey].self, forKey: .camelVirtualKeys) {
            self.virtualKeys = virtualKeys
        } else {
            self.virtualKeys = try container.decode([VirtualKey].self, forKey: .data)
        }
    }
}

struct BudgetsResponse: Decodable {
    let budgets: [Budget]
}

struct VirtualKey: Decodable {
    let id: String
    let name: String?
    let budgets: [Budget]
    let providerConfigs: [ProviderConfig]
    let calendarAligned: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case budgets
        case providerConfigs = "provider_configs"
        case calendarAligned = "calendar_aligned"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.budgets = try container.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
        self.providerConfigs = try container.decodeIfPresent([ProviderConfig].self, forKey: .providerConfigs) ?? []
        self.calendarAligned = try container.decodeIfPresent(Bool.self, forKey: .calendarAligned)
    }

    init(id: String, name: String?, budgets: [Budget], providerConfigs: [ProviderConfig], calendarAligned: Bool?) {
        self.id = id
        self.name = name
        self.budgets = budgets
        self.providerConfigs = providerConfigs
        self.calendarAligned = calendarAligned
    }
}

struct Budget: Decodable {
    let id: String?
    let maxLimit: Double
    let currentUsage: Double
    let resetDuration: String
    let lastReset: String?
    let virtualKeyID: String?
    let providerConfigID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case maxLimit = "max_limit"
        case currentUsage = "current_usage"
        case resetDuration = "reset_duration"
        case lastReset = "last_reset"
        case virtualKeyID = "virtual_key_id"
        case providerConfigID = "provider_config_id"
    }
}

struct ProviderConfig: Decodable {
    let id: Int?
    let provider: String
    let weight: Double?
    let allowedModels: [String]
    let blacklistedModels: [String]
    let allowAllKeys: Bool
    let keys: [DBKey]
    let budgets: [Budget]

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case weight
        case allowedModels = "allowed_models"
        case blacklistedModels = "blacklisted_models"
        case allowAllKeys = "allow_all_keys"
        case keys
        case budgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int.self, forKey: .id)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        self.allowedModels = try container.decodeIfPresent([String].self, forKey: .allowedModels) ?? []
        self.blacklistedModels = try container.decodeIfPresent([String].self, forKey: .blacklistedModels) ?? []
        self.allowAllKeys = try container.decodeIfPresent(Bool.self, forKey: .allowAllKeys) ?? false
        self.keys = try container.decodeIfPresent([DBKey].self, forKey: .keys) ?? []
        self.budgets = try container.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
    }

    init(
        id: Int?,
        provider: String,
        weight: Double?,
        allowedModels: [String],
        blacklistedModels: [String],
        allowAllKeys: Bool,
        keys: [DBKey],
        budgets: [Budget]
    ) {
        self.id = id
        self.provider = provider
        self.weight = weight
        self.allowedModels = allowedModels
        self.blacklistedModels = blacklistedModels
        self.allowAllKeys = allowAllKeys
        self.keys = keys
        self.budgets = budgets
    }
}

struct DBKey: Decodable {
    let keyID: String

    enum CodingKeys: String, CodingKey {
        case keyID = "key_id"
    }
}

enum BudgetScope {
    case common
    case provider(String)
}

struct BudgetTarget {
    let scope: BudgetScope
    let budget: Budget

    var key: String {
        switch scope {
        case .common:
            return "common:\(budget.id ?? budget.resetDuration)"
        case .provider(let provider):
            return "provider:\(provider):\(budget.id ?? budget.resetDuration)"
        }
    }

    var title: String {
        switch scope {
        case .common:
            return String(format: "%@ / $%.2f limit", budget.resetDuration, budget.maxLimit)
        case .provider(let provider):
            return "\(provider) / \(budget.id ?? budget.resetDuration)"
        }
    }

    var providerName: String? {
        if case .provider(let provider) = scope {
            return provider
        }
        return nil
    }
}

struct BudgetUpdate: Encodable {
    let maxLimit: Double
    let resetDuration: String

    enum CodingKeys: String, CodingKey {
        case maxLimit = "max_limit"
        case resetDuration = "reset_duration"
    }
}

struct ProviderConfigUpdate: Encodable {
    let id: Int?
    let provider: String
    let weight: Double?
    let allowedModels: [String]
    let blacklistedModels: [String]
    let keyIDs: [String]
    let budgets: [BudgetUpdate]

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case weight
        case allowedModels = "allowed_models"
        case blacklistedModels = "blacklisted_models"
        case keyIDs = "key_ids"
        case budgets
    }
}

struct BudgetUpdatePayload: Encodable {
    let budgets: [BudgetUpdate]
    let resetBudgetUsage: Bool?
    let calendarAligned: Bool?

    enum CodingKeys: String, CodingKey {
        case budgets
        case resetBudgetUsage = "reset_budget_usage"
        case calendarAligned = "calendar_aligned"
    }
}

struct ProviderBudgetUpdatePayload: Encodable {
    let providerConfigs: [ProviderConfigUpdate]
    let resetBudgetUsage: Bool?
    let calendarAligned: Bool?

    enum CodingKeys: String, CodingKey {
        case providerConfigs = "provider_configs"
        case resetBudgetUsage = "reset_budget_usage"
        case calendarAligned = "calendar_aligned"
    }
}

enum BifrostGaugeError: LocalizedError {
    case missingBudget
    case missingVirtualKey
    case httpStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingBudget:
            return "No matching Bifrost budget was found."
        case .missingVirtualKey:
            return "No registered Bifrost Virtual Keys were found."
        case .httpStatus(let status, let body):
            return "Bifrost returned HTTP \(status): \(body)"
        case .invalidResponse:
            return "Bifrost returned an invalid response."
        }
    }
}

final class BifrostClient: @unchecked Sendable {
    private let settings: AppSettings
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(settings: AppSettings) {
        self.settings = settings
        self.session = URLSession(configuration: .ephemeral)
    }

    func fetchVirtualKeys(completion: @escaping @Sendable (Result<[VirtualKey], Error>) -> Void) {
        var request = URLRequest(url: virtualKeysURL())
        request.httpMethod = "GET"
        applyHeaders(to: &request)

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(BifrostGaugeError.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(BifrostGaugeError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            do {
                completion(.success(try decoder.decode(VirtualKeysResponse.self, from: data).virtualKeys))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchVirtualKey(id: String? = nil, completion: @escaping @Sendable (Result<VirtualKey, Error>) -> Void) {
        var request = URLRequest(url: virtualKeyURL(id: id))
        request.httpMethod = "GET"
        applyHeaders(to: &request)

        session.dataTask(with: request) { [weak self, decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let self else {
                completion(.failure(BifrostGaugeError.invalidResponse))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(BifrostGaugeError.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(BifrostGaugeError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            do {
                let virtualKey = try decoder.decode(VirtualKeyResponse.self, from: data).virtualKey
                self.fetchBudgets { budgetsResult in
                    switch budgetsResult {
                    case .success(let budgets):
                        completion(.success(self.merging(budgets: budgets, into: virtualKey)))
                    case .failure:
                        completion(.success(virtualKey))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func resetBudgetUsage(virtualKey: VirtualKey, target: BudgetTarget, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        switch target.scope {
        case .common:
            updateCommonBudgets(virtualKey: virtualKey, budgets: virtualKey.budgets, resetUsage: true, completion: completion)
        case .provider(let provider):
            updateProviderBudgets(virtualKey: virtualKey, provider: provider, transform: { $0 }, resetUsage: true, completion: completion)
        }
    }

    func raiseBudget(virtualKey: VirtualKey, target: BudgetTarget, amount: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        setBudgetLimit(virtualKey: virtualKey, target: target, maxLimit: target.budget.maxLimit + amount, completion: completion)
    }

    func setBudgetLimit(virtualKey: VirtualKey, target: BudgetTarget, maxLimit: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        switch target.scope {
        case .common:
            let updates = virtualKey.budgets.map { budget -> BudgetUpdate in
                let shouldUpdate = budgetMatches(budget, target.budget)
                return BudgetUpdate(maxLimit: shouldUpdate ? maxLimit : budget.maxLimit, resetDuration: budget.resetDuration)
            }
            updateCommonBudgetPayload(budgets: updates, resetUsage: nil, calendarAligned: virtualKey.calendarAligned, completion: completion)
        case .provider(let provider):
            updateProviderBudgets(virtualKey: virtualKey, provider: provider, transform: { budgets in
                budgets.map { budget in
                    let shouldUpdate = budgetUpdateMatches(budget, target.budget)
                    return BudgetUpdate(maxLimit: shouldUpdate ? maxLimit : budget.maxLimit, resetDuration: budget.resetDuration)
                }
            }, resetUsage: nil, completion: completion)
        }
    }

    func setBudgetResetDuration(virtualKey: VirtualKey, target: BudgetTarget, resetDuration: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        switch target.scope {
        case .common:
            let updates = virtualKey.budgets.map { budget -> BudgetUpdate in
                let shouldUpdate = budgetMatches(budget, target.budget)
                return BudgetUpdate(
                    maxLimit: budget.maxLimit,
                    resetDuration: shouldUpdate ? resetDuration : budget.resetDuration
                )
            }
            updateCommonBudgetPayload(budgets: updates, resetUsage: nil, calendarAligned: virtualKey.calendarAligned, completion: completion)
        case .provider(let provider):
            updateProviderBudgets(virtualKey: virtualKey, provider: provider, transform: { budgets in
                budgets.map { budget in
                    let shouldUpdate = budgetUpdateMatches(budget, target.budget)
                    return BudgetUpdate(
                        maxLimit: budget.maxLimit,
                        resetDuration: shouldUpdate ? resetDuration : budget.resetDuration
                    )
                }
            }, resetUsage: nil, completion: completion)
        }
    }

    func setCalendarAligned(virtualKey: VirtualKey, target: BudgetTarget, calendarAligned: Bool, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        switch target.scope {
        case .common:
            updateCommonBudgets(
                virtualKey: virtualKey,
                budgets: virtualKey.budgets,
                resetUsage: nil,
                calendarAligned: calendarAligned,
                completion: completion
            )
        case .provider(let provider):
            updateProviderBudgets(
                virtualKey: virtualKey,
                provider: provider,
                transform: { $0 },
                resetUsage: nil,
                calendarAligned: calendarAligned,
                completion: completion
            )
        }
    }

    func addVendorBudget(virtualKey: VirtualKey, provider: String, maxLimit: Double, resetDuration: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        updateProviderBudgets(virtualKey: virtualKey, provider: provider, transform: { budgets in
            var updates = budgets
            if let index = updates.firstIndex(where: { $0.resetDuration == resetDuration }) {
                updates[index] = BudgetUpdate(maxLimit: maxLimit, resetDuration: resetDuration)
            } else {
                updates.append(BudgetUpdate(maxLimit: maxLimit, resetDuration: resetDuration))
            }
            return updates
        }, resetUsage: nil, completion: completion)
    }

    func selectedTarget(from virtualKey: VirtualKey) -> BudgetTarget? {
        let config = settings.currentConfig()
        let targets = budgetTargets(from: virtualKey)

        if let resetDuration = config.resetDuration,
           let target = targets.first(where: { $0.budget.resetDuration == resetDuration }) {
            return target
        }
        if let monthly = targets.first(where: { $0.budget.resetDuration == "1M" }) {
            return monthly
        }
        return targets.first
    }

    func budgetTargets(from virtualKey: VirtualKey) -> [BudgetTarget] {
        virtualKey.budgets.map { BudgetTarget(scope: .common, budget: $0) }
    }

    private func updateCommonBudgets(
        virtualKey: VirtualKey,
        budgets: [Budget],
        resetUsage: Bool?,
        calendarAligned: Bool? = nil,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let updates = budgets.map {
            BudgetUpdate(maxLimit: $0.maxLimit, resetDuration: $0.resetDuration)
        }
        updateCommonBudgetPayload(
            budgets: updates,
            resetUsage: resetUsage,
            calendarAligned: calendarAligned ?? virtualKey.calendarAligned,
            completion: completion
        )
    }

    private func updateCommonBudgetPayload(budgets: [BudgetUpdate], resetUsage: Bool?, calendarAligned: Bool?, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        let payload = BudgetUpdatePayload(
            budgets: budgets,
            resetBudgetUsage: resetUsage,
            calendarAligned: calendarAligned
        )

        do {
            var request = URLRequest(url: virtualKeyURL())
            request.httpMethod = "PUT"
            request.httpBody = try encoder.encode(payload)
            applyHeaders(to: &request)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            session.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(BifrostGaugeError.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(BifrostGaugeError.httpStatus(http.statusCode, String(data: data ?? Data(), encoding: .utf8) ?? "")))
                    return
                }
                completion(.success(()))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    private func updateProviderBudgets(
        virtualKey: VirtualKey,
        provider: String,
        transform: ([BudgetUpdate]) -> [BudgetUpdate],
        resetUsage: Bool?,
        calendarAligned: Bool? = nil,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let updates = virtualKey.providerConfigs.map { providerConfig -> ProviderConfigUpdate in
            let currentBudgets = providerConfig.budgets.map {
                BudgetUpdate(maxLimit: $0.maxLimit, resetDuration: $0.resetDuration)
            }
            return ProviderConfigUpdate(
                id: providerConfig.id,
                provider: providerConfig.provider,
                weight: providerConfig.weight,
                allowedModels: providerConfig.allowedModels,
                blacklistedModels: providerConfig.blacklistedModels,
                keyIDs: providerConfig.allowAllKeys ? ["*"] : providerConfig.keys.map(\.keyID),
                budgets: providerConfig.provider == provider ? transform(currentBudgets) : currentBudgets
            )
        }
        updateProviderBudgetPayload(
            providerConfigs: updates,
            resetUsage: resetUsage,
            calendarAligned: calendarAligned ?? virtualKey.calendarAligned,
            completion: completion
        )
    }

    private func updateProviderBudgetPayload(providerConfigs: [ProviderConfigUpdate], resetUsage: Bool?, calendarAligned: Bool?, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        let payload = ProviderBudgetUpdatePayload(
            providerConfigs: providerConfigs,
            resetBudgetUsage: resetUsage,
            calendarAligned: calendarAligned
        )

        do {
            var request = URLRequest(url: virtualKeyURL())
            request.httpMethod = "PUT"
            request.httpBody = try encoder.encode(payload)
            applyHeaders(to: &request)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            session.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(BifrostGaugeError.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(BifrostGaugeError.httpStatus(http.statusCode, String(data: data ?? Data(), encoding: .utf8) ?? "")))
                    return
                }
                completion(.success(()))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    private func budgetMatches(_ left: Budget, _ right: Budget) -> Bool {
        return left.resetDuration == right.resetDuration
    }

    private func budgetUpdateMatches(_ left: BudgetUpdate, _ right: Budget) -> Bool {
        return left.resetDuration == right.resetDuration
    }

    private func fetchBudgets(completion: @escaping @Sendable (Result<[Budget], Error>) -> Void) {
        var request = URLRequest(url: budgetsURL())
        request.httpMethod = "GET"
        applyHeaders(to: &request)

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(BifrostGaugeError.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(BifrostGaugeError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            do {
                completion(.success(try decoder.decode(BudgetsResponse.self, from: data).budgets))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func merging(budgets: [Budget], into virtualKey: VirtualKey) -> VirtualKey {
        let commonBudgets = virtualKey.budgets.isEmpty
            ? mergedBudgets(
                existing: virtualKey.budgets,
                additional: budgets.filter { $0.virtualKeyID == virtualKey.id }
            )
            : virtualKey.budgets
        let providerConfigs = virtualKey.providerConfigs.map { providerConfig in
            let providerBudgets = budgets.filter { $0.providerConfigID == providerConfig.id }
            return ProviderConfig(
                id: providerConfig.id,
                provider: providerConfig.provider,
                weight: providerConfig.weight,
                allowedModels: providerConfig.allowedModels,
                blacklistedModels: providerConfig.blacklistedModels,
                allowAllKeys: providerConfig.allowAllKeys,
                keys: providerConfig.keys,
                budgets: providerConfig.budgets.isEmpty
                    ? mergedBudgets(existing: providerConfig.budgets, additional: providerBudgets)
                    : providerConfig.budgets
            )
        }
        return VirtualKey(
            id: virtualKey.id,
            name: virtualKey.name,
            budgets: commonBudgets,
            providerConfigs: providerConfigs,
            calendarAligned: virtualKey.calendarAligned
        )
    }

    private func mergedBudgets(existing: [Budget], additional: [Budget]) -> [Budget] {
        additional.reduce(existing) { partial, budget in
            if partial.contains(where: { budgetMatches($0, budget) }) {
                return partial
            }
            return partial + [budget]
        }
    }

    func defaultResetDuration(from virtualKey: VirtualKey) -> String? {
        let targets = budgetTargets(from: virtualKey)
        if let monthly = targets.first(where: { $0.budget.resetDuration == "1M" }) {
            return monthly.budget.resetDuration
        }
        return targets.first?.budget.resetDuration
    }

    private func virtualKeysURL() -> URL {
        settings.currentConfig().baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("governance")
            .appendingPathComponent("virtual-keys")
    }

    private func virtualKeyURL(id: String? = nil) -> URL {
        let config = settings.currentConfig()
        return virtualKeysURL()
            .appendingPathComponent(id ?? config.virtualKeyID)
    }

    private func budgetsURL() -> URL {
        settings.currentConfig().baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("governance")
            .appendingPathComponent("budgets")
    }

    private func applyHeaders(to request: inout URLRequest) {
        if let token = settings.currentConfig().adminToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let client: BifrostClient
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let summaryItem = NSMenuItem(title: "Loading Bifrost budget...", action: nil, keyEquivalent: "")
    private let usageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let resetDurationItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let budgetActionsItem = NSMenuItem(title: "Budget Actions", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "Reset Now", action: #selector(resetBudgetUsage), keyEquivalent: "r")
    private let raiseDefaultItem = NSMenuItem(title: "", action: #selector(raiseBudgetDefault), keyEquivalent: "+")
    private let raiseCustomItem = NSMenuItem(title: "Raise Budget...", action: #selector(raiseBudgetCustom), keyEquivalent: "=")
    private let budgetSettingsItem = NSMenuItem(title: "Budget Settings", action: nil, keyEquivalent: "")
    private let setBudgetLimitItem = NSMenuItem(title: "Set Budget Limit...", action: #selector(setSelectedBudgetLimit), keyEquivalent: "l")
    private let budgetEnforcementItem = NSMenuItem(title: "", action: #selector(toggleBudgetEnforcement), keyEquivalent: "")
    private let setDefaultRaiseAmountItem = NSMenuItem(title: "Set Default Raise Amount...", action: #selector(setDefaultRaiseAmount), keyEquivalent: "d")
    private let calendarAlignedItem = NSMenuItem(title: "Calendar Aligned Resets", action: #selector(toggleCalendarAligned), keyEquivalent: "")
    private let virtualKeyItem = NSMenuItem(title: "Virtual Key", action: nil, keyEquivalent: "")
    private let displayedBudgetMenuItem = NSMenuItem(title: "Budget Window", action: nil, keyEquivalent: "")
    private let budgetResetItem = NSMenuItem(title: "Bifrost Budget Reset", action: nil, keyEquivalent: "")
    private let menuBarDisplayItem = NSMenuItem(title: "Menu Bar Display", action: nil, keyEquivalent: "")
    private let refreshIntervalItem = NSMenuItem(title: "", action: #selector(setRefreshSeconds), keyEquivalent: "")
    private let aboutItem = NSMenuItem(title: "About Bifrost...", action: #selector(showAboutBifrost), keyEquivalent: "")
    private var timer: Timer?
    private var registeredVirtualKeys: [VirtualKey] = []
    private var currentVirtualKey: VirtualKey?
    private var currentTarget: BudgetTarget?

    init(settings: AppSettings) {
        self.settings = settings
        self.client = BifrostClient(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refresh()
        scheduleRefreshTimer()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = " --"
        }

        summaryItem.isEnabled = false
        usageItem.isEnabled = false
        resetDurationItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(usageItem)
        menu.addItem(resetDurationItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "u"))
        menu.addItem(budgetActionsMenu())
        menu.addItem(budgetSettingsMenu())
        menu.addItem(.separator())
        menu.addItem(virtualKeyMenu())
        menu.addItem(.separator())
        menu.addItem(menuBarDisplayMenu())
        menu.addItem(settingsMenu())
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "Open Bifrost", action: #selector(openBifrost), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        updateMenuTargets(menu)
        statusItem.menu = menu
        updateStaticMenuState()
    }

    private func budgetResetMenu() -> NSMenuItem {
        let submenu = NSMenu()
        for window in BudgetResetWindow.allCases {
            let child = NSMenuItem(title: window.title, action: #selector(setSelectedBudgetResetDuration(_:)), keyEquivalent: "")
            child.representedObject = window.rawValue
            submenu.addItem(child)
        }
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: "Set Custom Reset Duration...", action: #selector(setCustomBudgetResetDuration), keyEquivalent: ""))
        submenu.addItem(.separator())
        submenu.addItem(calendarAlignedItem)
        budgetResetItem.submenu = submenu
        return budgetResetItem
    }

    private func virtualKeyMenu() -> NSMenuItem {
        virtualKeyItem.submenu = NSMenu()
        return virtualKeyItem
    }

    private func budgetActionsMenu() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.addItem(resetItem)
        submenu.addItem(.separator())
        submenu.addItem(raiseDefaultItem)
        submenu.addItem(raiseCustomItem)
        budgetActionsItem.submenu = submenu
        return budgetActionsItem
    }

    private func budgetSettingsMenu() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.addItem(setBudgetLimitItem)
        submenu.addItem(displayedBudgetMenuItem)
        submenu.addItem(budgetEnforcementItem)
        submenu.addItem(.separator())
        submenu.addItem(setDefaultRaiseAmountItem)
        submenu.addItem(.separator())
        submenu.addItem(budgetResetMenu())
        budgetSettingsItem.submenu = submenu
        return budgetSettingsItem
    }

    private func menuBarDisplayMenu() -> NSMenuItem {
        let submenu = NSMenu()
        for mode in MenuBarDisplayMode.allCases {
            let child = NSMenuItem(title: mode.title, action: #selector(setMenuBarDisplayMode(_:)), keyEquivalent: "")
            child.representedObject = mode.rawValue
            submenu.addItem(child)
        }
        menuBarDisplayItem.submenu = submenu
        return menuBarDisplayItem
    }

    private func settingsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Bifrost Settings", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(NSMenuItem(title: "Set Base URL...", action: #selector(setBaseURL), keyEquivalent: ""))
        submenu.addItem(refreshIntervalItem)
        item.submenu = submenu
        return item
    }

    private func updateMenuTargets(_ menu: NSMenu) {
        for item in menu.items {
            item.target = self
            if let submenu = item.submenu {
                updateMenuTargets(submenu)
            }
        }
    }

    @objc private func refresh() {
        setLoading()
        client.fetchVirtualKeys { [weak self] result in
            DispatchQueue.main.async {
                self?.handleVirtualKeysFetch(result)
            }
        }
    }

    @objc private func resetBudgetUsage() {
        performReset(interactive: true)
    }

    @objc private func raiseBudgetDefault() {
        raiseBudget(by: settings.defaultRaiseAmount)
    }

    @objc private func raiseBudgetCustom() {
        guard let amount = promptDouble(
            title: "Raise Budget",
            message: "Enter the amount to add to the selected budget.",
            defaultValue: settings.defaultRaiseAmount
        ) else {
            return
        }
        raiseBudget(by: amount)
    }

    @objc private func setDefaultRaiseAmount() {
        guard let amount = promptDouble(
            title: "Default Raise Amount",
            message: "Enter the default amount used by Raise Budget.",
            defaultValue: settings.defaultRaiseAmount
        ) else {
            return
        }
        settings.defaultRaiseAmount = amount
        updateStaticMenuState()
    }

    @objc private func setRefreshSeconds() {
        guard let value = promptString(
            title: "Refresh Period",
            message: "Enter seconds between automatic Bifrost refreshes. Minimum: \(Int(AppConfig.minimumRefreshSeconds)).",
            defaultValue: refreshSecondsInputValue(settings.refreshSeconds)
        ) else {
            return
        }
        guard let seconds = TimeInterval(value), seconds > 0 else {
            showAlert(title: "Invalid refresh interval", message: "Enter a positive number of seconds.")
            return
        }
        settings.refreshSeconds = seconds
        scheduleRefreshTimer()
        updateStaticMenuState()
    }

    @objc private func setSelectedBudgetLimit() {
        guard let virtualKey = currentVirtualKey, let target = currentTarget else {
            showAlert(title: "Budget is not loaded", message: "Refresh Bifrost budget data before editing the limit.")
            return
        }
        guard let maxLimit = promptDouble(
            title: "Set Budget Limit",
            message: "Enter the new max_limit for \(target.title).",
            defaultValue: target.budget.maxLimit
        ) else {
            return
        }
        setActionsEnabled(false)
        client.setBudgetLimit(virtualKey: virtualKey, target: target, maxLimit: maxLimit) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    self?.settings.setDisabledBudgetLimit(nil, forVirtualKeyID: virtualKey.id, budgetKey: target.key)
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Budget update failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    @objc private func toggleBudgetEnforcement() {
        guard let virtualKey = currentVirtualKey, let target = currentTarget else {
            showAlert(title: "Budget is not loaded", message: "Refresh Bifrost budget data before toggling enforcement.")
            return
        }

        let savedLimit = settings.disabledBudgetLimit(forVirtualKeyID: virtualKey.id, budgetKey: target.key)
        let nextLimit = savedLimit ?? AppSettings.inactiveBudgetLimit
        let enabling = savedLimit != nil

        if !enabling {
            let alert = NSAlert()
            alert.messageText = "Allow over-budget requests?"
            alert.informativeText = "This keeps the budget entry but raises max_limit to a local high-water value, so Bifrost will not block requests after the current limit is reached. The current limit is saved and can be restored from this menu."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        setActionsEnabled(false)
        client.setBudgetLimit(virtualKey: virtualKey, target: target, maxLimit: nextLimit) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    if enabling {
                        self?.settings.setDisabledBudgetLimit(nil, forVirtualKeyID: virtualKey.id, budgetKey: target.key)
                    } else {
                        self?.settings.setDisabledBudgetLimit(target.budget.maxLimit, forVirtualKeyID: virtualKey.id, budgetKey: target.key)
                    }
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Budget enforcement update failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    @objc private func selectDisplayedBudget(_ sender: NSMenuItem) {
        guard let resetDuration = sender.representedObject as? String else {
            return
        }
        settings.resetDuration = resetDuration
        refresh()
    }

    @objc private func setSelectedBudgetResetDuration(_ sender: NSMenuItem) {
        guard let resetDuration = sender.representedObject as? String else {
            return
        }
        updateSelectedBudgetResetDuration(resetDuration)
    }

    @objc private func setMenuBarDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = MenuBarDisplayMode(rawValue: raw) else {
            return
        }
        settings.menuBarDisplayMode = mode
        if let virtualKey = currentVirtualKey, let target = currentTarget {
            updateMenu(virtualKey: virtualKey, target: target)
        } else {
            updateStaticMenuState()
        }
    }

    @objc private func setCustomBudgetResetDuration() {
        guard let target = currentTarget else {
            showAlert(title: "Budget is not loaded", message: "Refresh Bifrost budget data before editing reset duration.")
            return
        }
        guard let resetDuration = promptString(
            title: "Bifrost Budget Reset Duration",
            message: "Example: 1d, 1w, 1M",
            defaultValue: target.budget.resetDuration
        ), !resetDuration.isEmpty else {
            return
        }
        updateSelectedBudgetResetDuration(resetDuration)
    }

    @objc private func toggleCalendarAligned() {
        guard let virtualKey = currentVirtualKey, let target = currentTarget else {
            showAlert(title: "Budget is not loaded", message: "Refresh Bifrost budget data before editing reset alignment.")
            return
        }

        let nextValue = !(virtualKey.calendarAligned ?? false)
        guard !nextValue || supportsCalendarAligned(resetDuration: target.budget.resetDuration) else {
            showAlert(
                title: "Calendar alignment needs a longer reset",
                message: "Set the selected budget reset duration to a day, week, month, or year window before turning on Calendar Aligned Resets."
            )
            return
        }

        setActionsEnabled(false)
        client.setCalendarAligned(virtualKey: virtualKey, target: target, calendarAligned: nextValue) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Calendar alignment update failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    @objc private func setBaseURL() {
        guard let value = promptString(title: "Bifrost Base URL", message: "Example: http://127.0.0.1:18080", defaultValue: settings.baseURL.absoluteString),
              let url = URL(string: value) else {
            return
        }
        settings.baseURL = url
        refresh()
    }

    @objc private func selectVirtualKey(_ sender: NSMenuItem) {
        guard let virtualKeyID = sender.representedObject as? String,
              virtualKeyID != settings.virtualKeyID else {
            return
        }
        settings.virtualKeyID = virtualKeyID
        if let virtualKey = registeredVirtualKeys.first(where: { $0.id == virtualKeyID }) {
            settings.resetDuration = client.defaultResetDuration(from: virtualKey)
        } else {
            settings.resetDuration = nil
        }
        refresh()
    }

    @objc private func clearBudgetSelection() {
        settings.resetDuration = nil
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAgentInstalled() {
                try uninstallLaunchAgent()
            } else {
                try installLaunchAgent()
            }
            updateStaticMenuState()
        } catch {
            showAlert(title: "Launch at Login update failed", message: error.localizedDescription)
        }
    }

    @objc private func openBifrost() {
        NSWorkspace.shared.open(settings.baseURL)
    }

    @objc private func showAboutBifrost() {
        let alert = NSAlert()
        alert.messageText = "About Bifrost"
        alert.informativeText = [
            "App: bifrost-gauge",
            "Version: \(AppMetadata.versionDescription)",
            "Bifrost URL: \(settings.baseURL.absoluteString)",
            "Virtual Key: \(virtualKeyDisplayName())",
            "Budget Window: \(currentTarget?.title ?? "Unavailable")",
            "Menu Bar Display: \(settings.menuBarDisplayMode.title)",
            "Refresh Period: \(formatRefreshSeconds(settings.refreshSeconds))"
        ].joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handleVirtualKeysFetch(_ result: Result<[VirtualKey], Error>) {
        switch result {
        case .success(let virtualKeys):
            registeredVirtualKeys = virtualKeys
            guard let selected = selectedRegisteredVirtualKey(from: virtualKeys) else {
                currentVirtualKey = nil
                currentTarget = nil
                setError(BifrostGaugeError.missingVirtualKey.localizedDescription)
                return
            }
            client.fetchVirtualKey(id: selected.id) { [weak self] result in
                DispatchQueue.main.async {
                    self?.handleFetch(result)
                }
            }
        case .failure(let error):
            registeredVirtualKeys = []
            currentVirtualKey = nil
            currentTarget = nil
            setError(error.localizedDescription)
        }
    }

    private func selectedRegisteredVirtualKey(from virtualKeys: [VirtualKey]) -> VirtualKey? {
        if let selected = virtualKeys.first(where: { $0.id == settings.virtualKeyID }) {
            return selected
        }
        guard let fallback = virtualKeys.first else {
            return nil
        }
        settings.virtualKeyID = fallback.id
        settings.resetDuration = client.defaultResetDuration(from: fallback)
        return fallback
    }

    private func handleFetch(_ result: Result<VirtualKey, Error>) {
        switch result {
        case .success(let virtualKey):
            currentVirtualKey = virtualKey
            guard let target = client.selectedTarget(from: virtualKey) else {
                currentTarget = nil
                setError(BifrostGaugeError.missingBudget.localizedDescription)
                return
            }
            currentTarget = target
            updateMenu(virtualKey: virtualKey, target: target)
        case .failure(let error):
            currentVirtualKey = nil
            currentTarget = nil
            setError(error.localizedDescription)
        }
    }

    private func performReset(interactive: Bool) {
        guard let virtualKey = currentVirtualKey, let target = currentTarget else {
            if interactive {
                showAlert(title: "Budget is not loaded", message: "Refresh Bifrost budget data before resetting.")
            }
            return
        }

        if interactive {
            let alert = NSAlert()
            alert.messageText = "Reset Bifrost budget usage?"
            alert.informativeText = "This sends reset_budget_usage=true for the current Virtual Key."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Reset")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        setActionsEnabled(false)
        client.resetBudgetUsage(virtualKey: virtualKey, target: target) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    self?.refresh()
                case .failure(let error):
                    if interactive {
                        self?.showAlert(title: "Reset failed", message: error.localizedDescription)
                    }
                    self?.refresh()
                }
            }
        }
    }

    private func updateSelectedBudgetResetDuration(_ resetDuration: String) {
        guard let virtualKey = currentVirtualKey, let target = currentTarget else {
            showAlert(title: "Budget is not loaded", message: "Refresh Bifrost budget data before editing reset duration.")
            return
        }
        guard virtualKey.calendarAligned != true || supportsCalendarAligned(resetDuration: resetDuration) else {
            showAlert(
                title: "Reset duration needs rolling alignment",
                message: "Turn off Calendar Aligned Resets before using minute or hour reset durations. Bifrost calendar_aligned supports day, week, month, and year windows."
            )
            return
        }

        setActionsEnabled(false)
        client.setBudgetResetDuration(virtualKey: virtualKey, target: target, resetDuration: resetDuration) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Reset duration update failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    private func supportsCalendarAligned(resetDuration: String) -> Bool {
        let trimmed = resetDuration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unit = trimmed.last else {
            return true
        }
        return unit != "m" && unit != "h"
    }

    private func raiseBudget(by amount: Double) {
        guard amount > 0 else {
            showAlert(title: "Invalid amount", message: "Budget raise amount must be greater than zero.")
            return
        }
        guard let virtualKey = currentVirtualKey, let target = currentTarget else {
            showAlert(title: "Budget is not loaded", message: "Refresh Bifrost budget data before raising the limit.")
            return
        }

        setActionsEnabled(false)
        client.raiseBudget(virtualKey: virtualKey, target: target, amount: amount) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Raise failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    private func setLoading() {
        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.image = nil
        statusItem.button?.title = " ..."
        summaryItem.title = "Refreshing Bifrost budget..."
        usageItem.title = ""
        updateStaticMenuState()
    }

    private func setError(_ message: String) {
        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.image = nil
        statusItem.button?.title = " !"
        summaryItem.title = "Bifrost budget unavailable"
        usageItem.title = message
        updateStaticMenuState()
    }

    private func updateMenu(virtualKey: VirtualKey, target: BudgetTarget) {
        let budget = target.budget
        let ratio = budget.maxLimit > 0 ? budget.currentUsage / budget.maxLimit : 0
        let percentage = min(999, ratio * 100)
        let remaining = max(0, budget.maxLimit - budget.currentUsage)
        updateStatusDisplay(percentage: percentage, ratio: ratio, spendAmount: budget.currentUsage)
        summaryItem.title = "\(virtualKey.name ?? virtualKey.id) / \(target.title)"
        if settings.disabledBudgetLimit(forVirtualKeyID: virtualKey.id, budgetKey: target.key) != nil {
            usageItem.title = String(
                format: "$%.2f used / over-budget requests allowed / original limit saved",
                budget.currentUsage
            )
        } else {
            usageItem.title = String(
                format: "$%.2f used / $%.2f limit / $%.2f left",
                budget.currentUsage,
                budget.maxLimit,
                remaining
            )
        }
        updateStaticMenuState()
    }

    private func updateStatusDisplay(percentage: Double, ratio: Double, spendAmount: Double) {
        guard let button = statusItem.button else {
            return
        }
        let mode = settings.menuBarDisplayMode
        var titleParts: [String] = []
        if mode.showsPercent {
            titleParts.append(String(format: "%.1f%%", percentage))
        }
        if mode.showsSpendAmount {
            titleParts.append(String(format: "$%.2f", spendAmount))
        }

        if mode.showsPie {
            button.image = makePieImage(ratio: ratio)
            button.imagePosition = titleParts.isEmpty ? .imageOnly : .imageLeft
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }

        if titleParts.isEmpty {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
        } else {
            statusItem.length = NSStatusItem.variableLength
            button.title = " " + titleParts.joined(separator: " ")
        }
    }

    private func makePieImage(ratio: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let clamped = max(0, min(1, ratio))
        let fillColor: NSColor
        switch ratio {
        case ..<0.8:
            fillColor = .controlAccentColor
        case ..<1.0:
            fillColor = .systemYellow
        default:
            fillColor = .systemRed
        }

        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: rect).fill()

        if clamped > 0 {
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - (360 * clamped),
                clockwise: true
            )
            path.close()
            fillColor.setFill()
            path.fill()
        }

        NSColor.labelColor.withAlphaComponent(0.65).setStroke()
        let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        outline.stroke()
        image.isTemplate = false
        return image
    }

    private func updateStaticMenuState() {
        budgetActionsItem.title = "Budget Actions"
        raiseDefaultItem.title = String(format: "Raise Budget by $%.2f", settings.defaultRaiseAmount)
        budgetSettingsItem.title = "Budget Settings"
        refreshIntervalItem.title = "Refresh Period: \(formatRefreshSeconds(settings.refreshSeconds))"
        budgetEnforcementItem.title = budgetEnforcementDescription()
        resetDurationItem.title = resetDurationDescription()
        virtualKeyItem.title = "Virtual Key: \(virtualKeyDisplayName())"
        launchAtLoginItem.state = launchAgentInstalled() ? .on : .off
        rebuildVirtualKeyMenu()
        rebuildDisplayedBudgetMenu()
        markBudgetResetMenu()
        markMenuBarDisplayMenu()
    }

    private func rebuildVirtualKeyMenu() {
        let submenu = NSMenu()
        let current = NSMenuItem(title: "Current: \(virtualKeyDisplayName())", action: nil, keyEquivalent: "")
        current.isEnabled = false
        submenu.addItem(current)
        submenu.addItem(.separator())
        if registeredVirtualKeys.isEmpty {
            let item = NSMenuItem(title: "No registered Virtual Keys", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        } else {
            for virtualKey in registeredVirtualKeys {
                let item = NSMenuItem(title: virtualKeyMenuTitle(virtualKey), action: #selector(selectVirtualKey(_:)), keyEquivalent: "")
                item.representedObject = virtualKey.id
                item.state = virtualKey.id == settings.virtualKeyID ? .on : .off
                item.target = self
                submenu.addItem(item)
            }
        }
        virtualKeyItem.submenu = submenu
        updateMenuTargets(submenu)
    }

    private func rebuildDisplayedBudgetMenu() {
        let submenu = NSMenu()
        let targets = currentVirtualKey.map { client.budgetTargets(from: $0) } ?? []
        if targets.isEmpty {
            let item = NSMenuItem(title: "No registered budgets", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        } else {
            for target in targets {
                let item = NSMenuItem(title: target.title, action: #selector(selectDisplayedBudget(_:)), keyEquivalent: "")
                item.representedObject = target.budget.resetDuration
                item.state = target.budget.resetDuration == currentTarget?.budget.resetDuration ? .on : .off
                item.target = self
                submenu.addItem(item)
            }
        }
        submenu.addItem(.separator())
        let defaultItem = NSMenuItem(title: "Use Default Budget Window", action: #selector(clearBudgetSelection), keyEquivalent: "")
        defaultItem.target = self
        submenu.addItem(defaultItem)
        displayedBudgetMenuItem.submenu = submenu
    }

    private func resetDurationDescription() -> String {
        guard let target = currentTarget else {
            return "Bifrost reset: Unavailable"
        }
        let alignment = currentVirtualKey?.calendarAligned == true ? "calendar aligned" : "rolling"
        return "Bifrost reset: \(target.budget.resetDuration) (\(alignment))"
    }

    private func budgetEnforcementDescription() -> String {
        guard let target = currentTarget, let virtualKey = currentVirtualKey else {
            return "Allow Over-Budget Requests: Unavailable"
        }
        if settings.disabledBudgetLimit(forVirtualKeyID: virtualKey.id, budgetKey: target.key) != nil {
            return "Allow Over-Budget Requests: On (Off restores saved limit)"
        }
        return "Allow Over-Budget Requests: Off"
    }

    private func virtualKeyDisplayName() -> String {
        if let virtualKey = currentVirtualKey, let name = virtualKey.name, !name.isEmpty {
            return "\(name) (\(virtualKey.id))"
        }
        return currentVirtualKey?.id ?? settings.virtualKeyID
    }

    private func virtualKeyMenuTitle(_ virtualKey: VirtualKey) -> String {
        guard let name = virtualKey.name, !name.isEmpty else {
            return virtualKey.id
        }
        return "\(name) (\(virtualKey.id))"
    }

    private func markBudgetResetMenu() {
        guard let submenu = budgetResetItem.submenu else {
            return
        }
        for child in submenu.items {
            guard !child.isSeparatorItem, child !== calendarAlignedItem else {
                continue
            }
            guard let raw = child.representedObject as? String else {
                child.state = .off
                child.isEnabled = currentTarget != nil
                continue
            }
            let disabledForCalendarAlignment = currentVirtualKey?.calendarAligned == true && !supportsCalendarAligned(resetDuration: raw)
            child.state = raw == currentTarget?.budget.resetDuration ? .on : .off
            child.isEnabled = currentTarget != nil && !disabledForCalendarAlignment
        }
        calendarAlignedItem.state = currentVirtualKey?.calendarAligned == true ? .on : .off
        calendarAlignedItem.isEnabled = currentTarget != nil
    }

    private func markMenuBarDisplayMenu() {
        guard let submenu = menuBarDisplayItem.submenu else {
            return
        }
        for item in submenu.items {
            guard let raw = item.representedObject as? String else {
                item.state = .off
                continue
            }
            item.state = raw == settings.menuBarDisplayMode.rawValue ? .on : .off
        }
    }

    private func setActionsEnabled(_ enabled: Bool) {
        resetItem.isEnabled = enabled
        raiseDefaultItem.isEnabled = enabled
        raiseCustomItem.isEnabled = enabled
        setBudgetLimitItem.isEnabled = enabled && currentTarget != nil
        displayedBudgetMenuItem.isEnabled = enabled && currentVirtualKey != nil
        budgetEnforcementItem.isEnabled = enabled && currentTarget != nil
        setDefaultRaiseAmountItem.isEnabled = enabled
        calendarAlignedItem.isEnabled = enabled && currentTarget != nil
    }

    private func scheduleRefreshTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func refreshSecondsInputValue(_ seconds: TimeInterval) -> String {
        let rounded = seconds.rounded()
        if abs(seconds - rounded) < 0.001 {
            return String(Int(rounded))
        }
        return String(format: "%.2f", seconds)
    }

    private func formatRefreshSeconds(_ seconds: TimeInterval) -> String {
        "\(refreshSecondsInputValue(seconds))s"
    }

    private func promptString(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func promptDouble(title: String, message: String, defaultValue: Double) -> Double? {
        guard let value = promptString(title: title, message: message, defaultValue: String(format: "%.2f", defaultValue)) else {
            return nil
        }
        return Double(value)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func launchAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.bifrost-gauge.menubar.plist")
    }

    private func installLaunchAgent() throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw BifrostGaugeError.invalidResponse
        }
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/bifrost-gauge")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let payload: [String: Any] = [
            "Label": "com.local.bifrost-gauge.menubar",
            "ProgramArguments": [executablePath],
            "EnvironmentVariables": [
                "BIFROST_BASE_URL": settings.baseURL.absoluteString,
                "BIFROST_VIRTUAL_KEY_ID": settings.virtualKeyID,
                "BIFROST_BUDGET_RESET_DURATION": settings.resetDuration ?? "",
                "BIFROST_REFRESH_SECONDS": String(Int(settings.refreshSeconds))
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logDir.appendingPathComponent("bifrost-gauge-launchd.out.log").path,
            "StandardErrorPath": logDir.appendingPathComponent("bifrost-gauge-launchd.err.log").path,
            "WorkingDirectory": FileManager.default.currentDirectoryPath
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private func uninstallLaunchAgent() throws {
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }
}

let initialConfig = AppConfig.load()
let settings = AppSettings(initial: initialConfig)
let app = NSApplication.shared
let delegate = AppDelegate(settings: settings)
app.delegate = delegate
app.run()
