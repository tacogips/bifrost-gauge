import AppKit
import Foundation

enum ResetSchedule: String, CaseIterable {
    case off
    case daily
    case weekly
    case monthly
    case cron

    var title: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .cron: return "Cron"
        }
    }
}

struct AppConfig {
    var baseURL: URL
    var virtualKeyID: String
    var budgetID: String?
    var resetDuration: String?
    var refreshSeconds: TimeInterval
    var adminToken: String?

    static func load() -> AppConfig {
        let env = ProcessInfo.processInfo.environment
        var config = AppConfig(
            baseURL: URL(string: env["BIFROST_BASE_URL"] ?? "http://127.0.0.1:18080")!,
            virtualKeyID: env["BIFROST_VIRTUAL_KEY_ID"] ?? "vk-personal",
            budgetID: emptyToNil(env["BIFROST_BUDGET_ID"]),
            resetDuration: emptyToNil(env["BIFROST_BUDGET_RESET_DURATION"]),
            refreshSeconds: TimeInterval(env["BIFROST_REFRESH_SECONDS"] ?? "") ?? 60,
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
            case "--budget-id":
                config.budgetID = value
            case "--reset-duration":
                config.resetDuration = value
            case "--refresh-seconds":
                config.refreshSeconds = max(10, TimeInterval(value) ?? config.refreshSeconds)
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
    private enum Key {
        static let baseURL = "baseURL"
        static let virtualKeyID = "virtualKeyID"
        static let budgetID = "budgetID"
        static let resetDuration = "resetDuration"
        static let refreshSeconds = "refreshSeconds"
        static let adminToken = "adminToken"
        static let defaultRaiseAmount = "defaultRaiseAmount"
        static let resetSchedule = "resetSchedule"
        static let cronExpression = "cronExpression"
        static let lastAutoResetStamp = "lastAutoResetStamp"
        static let displayBudgetKey = "displayBudgetKey"
    }

    private let defaults = UserDefaults.standard
    private let initial: AppConfig

    init(initial: AppConfig) {
        self.initial = initial
        if defaults.object(forKey: Key.defaultRaiseAmount) == nil {
            defaults.set(5.0, forKey: Key.defaultRaiseAmount)
        }
        if defaults.string(forKey: Key.resetSchedule) == nil {
            defaults.set(ResetSchedule.off.rawValue, forKey: Key.resetSchedule)
        }
        if defaults.string(forKey: Key.cronExpression) == nil {
            defaults.set("0 0 1 * *", forKey: Key.cronExpression)
        }
    }

    var baseURL: URL {
        get { URL(string: defaults.string(forKey: Key.baseURL) ?? initial.baseURL.absoluteString) ?? initial.baseURL }
        set { defaults.set(newValue.absoluteString, forKey: Key.baseURL) }
    }

    var virtualKeyID: String {
        get { defaults.string(forKey: Key.virtualKeyID) ?? initial.virtualKeyID }
        set { defaults.set(newValue, forKey: Key.virtualKeyID) }
    }

    var budgetID: String? {
        get { stringOrInitial(Key.budgetID, initial.budgetID) }
        set { setOptional(newValue, forKey: Key.budgetID) }
    }

    var resetDuration: String? {
        get { stringOrInitial(Key.resetDuration, initial.resetDuration) }
        set { setOptional(newValue, forKey: Key.resetDuration) }
    }

    var refreshSeconds: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.refreshSeconds)
            return value > 0 ? value : initial.refreshSeconds
        }
        set { defaults.set(max(10, newValue), forKey: Key.refreshSeconds) }
    }

    var adminToken: String? {
        get { stringOrInitial(Key.adminToken, initial.adminToken) }
        set { setOptional(newValue, forKey: Key.adminToken) }
    }

    var defaultRaiseAmount: Double {
        get {
            let value = defaults.double(forKey: Key.defaultRaiseAmount)
            return value > 0 ? value : 5.0
        }
        set { defaults.set(max(0.01, newValue), forKey: Key.defaultRaiseAmount) }
    }

    var resetSchedule: ResetSchedule {
        get { ResetSchedule(rawValue: defaults.string(forKey: Key.resetSchedule) ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Key.resetSchedule) }
    }

    var cronExpression: String {
        get { defaults.string(forKey: Key.cronExpression) ?? "0 0 1 * *" }
        set { defaults.set(newValue, forKey: Key.cronExpression) }
    }

    var lastAutoResetStamp: String? {
        get { defaults.string(forKey: Key.lastAutoResetStamp) }
        set { setOptional(newValue, forKey: Key.lastAutoResetStamp) }
    }

    var displayBudgetKey: String? {
        get { defaults.string(forKey: Key.displayBudgetKey) }
        set { setOptional(newValue, forKey: Key.displayBudgetKey) }
    }

    func currentConfig() -> AppConfig {
        AppConfig(
            baseURL: baseURL,
            virtualKeyID: virtualKeyID,
            budgetID: budgetID,
            resetDuration: resetDuration,
            refreshSeconds: refreshSeconds,
            adminToken: adminToken
        )
    }

    private func stringOrInitial(_ key: String, _ initialValue: String?) -> String? {
        if let saved = defaults.string(forKey: key), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved
        }
        return initialValue
    }

    private func setOptional(_ value: String?, forKey key: String) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }
}

struct VirtualKeyResponse: Decodable {
    let virtualKey: VirtualKey

    enum CodingKeys: String, CodingKey {
        case virtualKey = "virtual_key"
    }
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
}

struct Budget: Decodable {
    let id: String?
    let maxLimit: Double
    let currentUsage: Double
    let resetDuration: String
    let lastReset: String?

    enum CodingKeys: String, CodingKey {
        case id
        case maxLimit = "max_limit"
        case currentUsage = "current_usage"
        case resetDuration = "reset_duration"
        case lastReset = "last_reset"
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
            return "Common / \(budget.id ?? budget.resetDuration)"
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
    let id: String?
    let maxLimit: Double
    let resetDuration: String

    enum CodingKeys: String, CodingKey {
        case id
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

enum BudgetBarError: LocalizedError {
    case missingBudget
    case httpStatus(Int, String)
    case invalidResponse
    case invalidCron(String)

    var errorDescription: String? {
        switch self {
        case .missingBudget:
            return "No matching Bifrost budget was found."
        case .httpStatus(let status, let body):
            return "Bifrost returned HTTP \(status): \(body)"
        case .invalidResponse:
            return "Bifrost returned an invalid response."
        case .invalidCron(let expression):
            return "Invalid cron expression: \(expression)"
        }
    }
}

final class BifrostClient {
    private let settings: AppSettings
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(settings: AppSettings) {
        self.settings = settings
        self.session = URLSession(configuration: .ephemeral)
    }

    func fetchVirtualKey(completion: @escaping (Result<VirtualKey, Error>) -> Void) {
        var request = URLRequest(url: virtualKeyURL())
        request.httpMethod = "GET"
        applyHeaders(to: &request)

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(BudgetBarError.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(BudgetBarError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            do {
                completion(.success(try decoder.decode(VirtualKeyResponse.self, from: data).virtualKey))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func resetBudgetUsage(virtualKey: VirtualKey, target: BudgetTarget, completion: @escaping (Result<Void, Error>) -> Void) {
        switch target.scope {
        case .common:
            updateCommonBudgets(virtualKey: virtualKey, budgets: virtualKey.budgets, resetUsage: true, completion: completion)
        case .provider(let provider):
            updateProviderBudgets(virtualKey: virtualKey, provider: provider, transform: { $0 }, resetUsage: true, completion: completion)
        }
    }

    func raiseBudget(virtualKey: VirtualKey, target: BudgetTarget, amount: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        setBudgetLimit(virtualKey: virtualKey, target: target, maxLimit: target.budget.maxLimit + amount, completion: completion)
    }

    func setBudgetLimit(virtualKey: VirtualKey, target: BudgetTarget, maxLimit: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        switch target.scope {
        case .common:
            let updates = virtualKey.budgets.map { budget -> BudgetUpdate in
                let shouldUpdate = budgetMatches(budget, target.budget)
                return BudgetUpdate(id: budget.id, maxLimit: shouldUpdate ? maxLimit : budget.maxLimit, resetDuration: budget.resetDuration)
            }
            updateCommonBudgetPayload(budgets: updates, resetUsage: nil, calendarAligned: virtualKey.calendarAligned, completion: completion)
        case .provider(let provider):
            updateProviderBudgets(virtualKey: virtualKey, provider: provider, transform: { budgets in
                budgets.map { budget in
                    let shouldUpdate = budgetUpdateMatches(budget, target.budget)
                    return BudgetUpdate(id: budget.id, maxLimit: shouldUpdate ? maxLimit : budget.maxLimit, resetDuration: budget.resetDuration)
                }
            }, resetUsage: nil, completion: completion)
        }
    }

    func setCommonDefaultBudget(virtualKey: VirtualKey, maxLimit: Double, resetDuration: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var updates = virtualKey.budgets.map {
            BudgetUpdate(id: $0.id, maxLimit: $0.maxLimit, resetDuration: $0.resetDuration)
        }
        if let index = updates.firstIndex(where: { $0.resetDuration == resetDuration }) {
            updates[index] = BudgetUpdate(id: updates[index].id, maxLimit: maxLimit, resetDuration: resetDuration)
        } else {
            updates.append(BudgetUpdate(id: nil, maxLimit: maxLimit, resetDuration: resetDuration))
        }
        updateCommonBudgetPayload(budgets: updates, resetUsage: nil, calendarAligned: virtualKey.calendarAligned, completion: completion)
    }

    func addVendorBudget(virtualKey: VirtualKey, provider: String, maxLimit: Double, resetDuration: String, completion: @escaping (Result<Void, Error>) -> Void) {
        updateProviderBudgets(virtualKey: virtualKey, provider: provider, transform: { budgets in
            var updates = budgets
            if let index = updates.firstIndex(where: { $0.resetDuration == resetDuration }) {
                updates[index] = BudgetUpdate(id: updates[index].id, maxLimit: maxLimit, resetDuration: resetDuration)
            } else {
                updates.append(BudgetUpdate(id: nil, maxLimit: maxLimit, resetDuration: resetDuration))
            }
            return updates
        }, resetUsage: nil, completion: completion)
    }

    func selectedTarget(from virtualKey: VirtualKey) -> BudgetTarget? {
        let config = settings.currentConfig()
        let targets = budgetTargets(from: virtualKey)

        if let key = settings.displayBudgetKey,
           let target = targets.first(where: { $0.key == key }) {
            return target
        }
        if let budgetID = config.budgetID,
           let target = targets.first(where: { $0.budget.id == budgetID }) {
            return target
        }
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
        let common = virtualKey.budgets.map { BudgetTarget(scope: .common, budget: $0) }
        let providers = virtualKey.providerConfigs.flatMap { providerConfig in
            providerConfig.budgets.map {
                BudgetTarget(scope: .provider(providerConfig.provider), budget: $0)
            }
        }
        return common + providers
    }

    private func updateCommonBudgets(virtualKey: VirtualKey, budgets: [Budget], resetUsage: Bool?, completion: @escaping (Result<Void, Error>) -> Void) {
        let updates = budgets.map {
            BudgetUpdate(id: $0.id, maxLimit: $0.maxLimit, resetDuration: $0.resetDuration)
        }
        updateCommonBudgetPayload(budgets: updates, resetUsage: resetUsage, calendarAligned: virtualKey.calendarAligned, completion: completion)
    }

    private func updateCommonBudgetPayload(budgets: [BudgetUpdate], resetUsage: Bool?, calendarAligned: Bool?, completion: @escaping (Result<Void, Error>) -> Void) {
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
                    completion(.failure(BudgetBarError.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(BudgetBarError.httpStatus(http.statusCode, String(data: data ?? Data(), encoding: .utf8) ?? "")))
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
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let updates = virtualKey.providerConfigs.map { providerConfig -> ProviderConfigUpdate in
            let currentBudgets = providerConfig.budgets.map {
                BudgetUpdate(id: $0.id, maxLimit: $0.maxLimit, resetDuration: $0.resetDuration)
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
        updateProviderBudgetPayload(providerConfigs: updates, resetUsage: resetUsage, calendarAligned: virtualKey.calendarAligned, completion: completion)
    }

    private func updateProviderBudgetPayload(providerConfigs: [ProviderConfigUpdate], resetUsage: Bool?, calendarAligned: Bool?, completion: @escaping (Result<Void, Error>) -> Void) {
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
                    completion(.failure(BudgetBarError.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(BudgetBarError.httpStatus(http.statusCode, String(data: data ?? Data(), encoding: .utf8) ?? "")))
                    return
                }
                completion(.success(()))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    private func budgetMatches(_ left: Budget, _ right: Budget) -> Bool {
        if let leftID = left.id, let rightID = right.id {
            return leftID == rightID
        }
        return left.resetDuration == right.resetDuration
    }

    private func budgetUpdateMatches(_ left: BudgetUpdate, _ right: Budget) -> Bool {
        if let leftID = left.id, let rightID = right.id {
            return leftID == rightID
        }
        return left.resetDuration == right.resetDuration
    }

    private func virtualKeyURL() -> URL {
        let config = settings.currentConfig()
        return config.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("governance")
            .appendingPathComponent("virtual-keys")
            .appendingPathComponent(config.virtualKeyID)
    }

    private func applyHeaders(to request: inout URLRequest) {
        if let token = settings.currentConfig().adminToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

struct CronExpression {
    let raw: String
    private let minute: CronField
    private let hour: CronField
    private let day: CronField
    private let month: CronField
    private let weekday: CronField

    init(_ raw: String) throws {
        let fields = raw.split(separator: " ").map(String.init)
        guard fields.count == 5 else {
            throw BudgetBarError.invalidCron(raw)
        }
        self.raw = raw
        self.minute = try CronField(fields[0], min: 0, max: 59)
        self.hour = try CronField(fields[1], min: 0, max: 23)
        self.day = try CronField(fields[2], min: 1, max: 31)
        self.month = try CronField(fields[3], min: 1, max: 12)
        self.weekday = try CronField(fields[4], min: 0, max: 7)
    }

    func matches(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        let cronWeekday = (components.weekday ?? 1) - 1
        return minute.contains(components.minute ?? -1) &&
            hour.contains(components.hour ?? -1) &&
            day.contains(components.day ?? -1) &&
            month.contains(components.month ?? -1) &&
            (weekday.contains(cronWeekday) || (cronWeekday == 0 && weekday.contains(7)))
    }
}

struct CronField {
    private let values: Set<Int>

    init(_ raw: String, min: Int, max: Int) throws {
        var result = Set<Int>()
        for part in raw.split(separator: ",").map(String.init) {
            let stepParts = part.split(separator: "/", maxSplits: 1).map(String.init)
            let base = stepParts[0]
            let step = stepParts.count == 2 ? Int(stepParts[1]) ?? 0 : 1
            guard step > 0 else { throw BudgetBarError.invalidCron(raw) }

            let range: ClosedRange<Int>
            if base == "*" {
                range = min...max
            } else if base.contains("-") {
                let bounds = base.split(separator: "-", maxSplits: 1).compactMap { Int($0) }
                guard bounds.count == 2, bounds[0] <= bounds[1], bounds[0] >= min, bounds[1] <= max else {
                    throw BudgetBarError.invalidCron(raw)
                }
                range = bounds[0]...bounds[1]
            } else if let value = Int(base), value >= min, value <= max {
                range = value...value
            } else {
                throw BudgetBarError.invalidCron(raw)
            }

            for value in range where (value - range.lowerBound).isMultiple(of: step) {
                result.insert(value)
            }
        }
        self.values = result
    }

    func contains(_ value: Int) -> Bool {
        values.contains(value)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let client: BifrostClient
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let summaryItem = NSMenuItem(title: "Loading Bifrost budget...", action: nil, keyEquivalent: "")
    private let usageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let scheduleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "Reset Now", action: #selector(resetBudgetUsage), keyEquivalent: "r")
    private let raiseDefaultItem = NSMenuItem(title: "", action: #selector(raiseBudgetDefault), keyEquivalent: "+")
    private let displayedBudgetMenuItem = NSMenuItem(title: "Displayed Budget", action: nil, keyEquivalent: "")
    private var timer: Timer?
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
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: "Bifrost budget")
            button.title = " --"
        }

        summaryItem.isEnabled = false
        usageItem.isEnabled = false
        scheduleItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(usageItem)
        menu.addItem(scheduleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "u"))
        menu.addItem(resetItem)
        menu.addItem(raiseDefaultItem)
        menu.addItem(NSMenuItem(title: "Raise Budget...", action: #selector(raiseBudgetCustom), keyEquivalent: "="))
        menu.addItem(NSMenuItem(title: "Set Selected Budget Limit...", action: #selector(setSelectedBudgetLimit), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Set Default Raise Amount...", action: #selector(setDefaultRaiseAmount), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(displayedBudgetMenuItem)
        menu.addItem(NSMenuItem(title: "Set Common Default Budget...", action: #selector(setCommonDefaultBudget), keyEquivalent: ""))
        menu.addItem(addVendorBudgetMenu())
        menu.addItem(.separator())
        menu.addItem(resetScheduleMenu())
        menu.addItem(settingsMenu())
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Bifrost", action: #selector(openBifrost), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        updateMenuTargets(menu)
        statusItem.menu = menu
        updateStaticMenuState()
    }

    private func resetScheduleMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Budget Reset Schedule", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for schedule in ResetSchedule.allCases {
            let child = NSMenuItem(title: schedule.title, action: #selector(setResetSchedule(_:)), keyEquivalent: "")
            child.representedObject = schedule.rawValue
            submenu.addItem(child)
        }
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: "Set Cron Expression...", action: #selector(setCronExpression), keyEquivalent: "c"))
        item.submenu = submenu
        return item
    }

    private func addVendorBudgetMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Add Vendor Budget", action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        return item
    }

    private func settingsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Bifrost Settings", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(NSMenuItem(title: "Set Base URL...", action: #selector(setBaseURL), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Set Virtual Key ID...", action: #selector(setVirtualKeyID), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Set Budget ID...", action: #selector(setBudgetID), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Set Budget Reset Duration...", action: #selector(setBudgetResetDuration), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Clear Budget Selection", action: #selector(clearBudgetSelection), keyEquivalent: ""))
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
        client.fetchVirtualKey { [weak self] result in
            DispatchQueue.main.async {
                self?.handleFetch(result)
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
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Budget update failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    @objc private func setCommonDefaultBudget() {
        guard let virtualKey = currentVirtualKey else {
            showAlert(title: "Virtual Key is not loaded", message: "Refresh Bifrost data before editing the common budget.")
            return
        }
        let defaultBudget = virtualKey.budgets.first(where: { $0.resetDuration == "1M" }) ?? virtualKey.budgets.first
        let maxLimit = promptDouble(
            title: "Common Default Budget",
            message: "Enter the common budget limit applied across all vendors.",
            defaultValue: defaultBudget?.maxLimit ?? 20.0
        )
        guard let maxLimit else {
            return
        }
        let resetDuration = promptString(
            title: "Common Default Reset Duration",
            message: "Example: 1d, 1w, 1M",
            defaultValue: defaultBudget?.resetDuration ?? "1M"
        )
        guard let resetDuration, !resetDuration.isEmpty else {
            return
        }

        setActionsEnabled(false)
        client.setCommonDefaultBudget(virtualKey: virtualKey, maxLimit: maxLimit, resetDuration: resetDuration) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Common budget update failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    @objc private func addVendorBudget(_ sender: NSMenuItem) {
        guard let virtualKey = currentVirtualKey,
              let provider = sender.representedObject as? String else {
            return
        }
        let existing = virtualKey.providerConfigs.first(where: { $0.provider == provider })?.budgets.first
        let maxLimit = promptDouble(
            title: "\(provider) Budget",
            message: "Enter the vendor-specific budget limit.",
            defaultValue: existing?.maxLimit ?? 20.0
        )
        guard let maxLimit else {
            return
        }
        let resetDuration = promptString(
            title: "\(provider) Reset Duration",
            message: "Example: 1d, 1w, 1M",
            defaultValue: existing?.resetDuration ?? settings.resetDuration ?? "1M"
        )
        guard let resetDuration, !resetDuration.isEmpty else {
            return
        }

        setActionsEnabled(false)
        client.addVendorBudget(virtualKey: virtualKey, provider: provider, maxLimit: maxLimit, resetDuration: resetDuration) { [weak self] result in
            DispatchQueue.main.async {
                self?.setActionsEnabled(true)
                switch result {
                case .success:
                    self?.refresh()
                case .failure(let error):
                    self?.showAlert(title: "Vendor budget update failed", message: error.localizedDescription)
                    self?.refresh()
                }
            }
        }
    }

    @objc private func selectDisplayedBudget(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else {
            return
        }
        settings.displayBudgetKey = key
        refresh()
    }

    @objc private func setResetSchedule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let schedule = ResetSchedule(rawValue: raw) else {
            return
        }
        settings.resetSchedule = schedule
        settings.lastAutoResetStamp = nil
        updateStaticMenuState()
    }

    @objc private func setCronExpression() {
        guard let expression = promptString(
            title: "Cron Reset Schedule",
            message: "Use five fields: minute hour day month weekday. Example: 0 0 1 * *",
            defaultValue: settings.cronExpression
        ) else {
            return
        }
        do {
            _ = try CronExpression(expression)
            settings.cronExpression = expression
            settings.resetSchedule = .cron
            settings.lastAutoResetStamp = nil
            updateStaticMenuState()
        } catch {
            showAlert(title: "Invalid cron expression", message: error.localizedDescription)
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

    @objc private func setVirtualKeyID() {
        guard let value = promptString(title: "Virtual Key ID", message: "Example: vk-personal", defaultValue: settings.virtualKeyID) else {
            return
        }
        settings.virtualKeyID = value
        refresh()
    }

    @objc private func setBudgetID() {
        guard let value = promptString(title: "Budget ID", message: "Example: budget-personal-daily-hard", defaultValue: settings.budgetID ?? "") else {
            return
        }
        settings.budgetID = value
        refresh()
    }

    @objc private func setBudgetResetDuration() {
        guard let value = promptString(title: "Budget Reset Duration", message: "Example: 1d, 1w, 1M", defaultValue: settings.resetDuration ?? "") else {
            return
        }
        settings.resetDuration = value
        refresh()
    }

    @objc private func clearBudgetSelection() {
        settings.budgetID = nil
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handleFetch(_ result: Result<VirtualKey, Error>) {
        switch result {
        case .success(let virtualKey):
            currentVirtualKey = virtualKey
            guard let target = client.selectedTarget(from: virtualKey) else {
                currentTarget = nil
                setError(BudgetBarError.missingBudget.localizedDescription)
                return
            }
            currentTarget = target
            updateMenu(virtualKey: virtualKey, target: target)
            maybeRunScheduledReset()
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

    private func maybeRunScheduledReset() {
        let schedule = settings.resetSchedule
        guard schedule != .off else {
            return
        }
        let now = Date()
        let calendar = Calendar.current
        guard shouldReset(schedule: schedule, now: now, calendar: calendar) else {
            return
        }
        let stamp = resetStamp(schedule: schedule, now: now, calendar: calendar)
        guard settings.lastAutoResetStamp != stamp else {
            return
        }
        settings.lastAutoResetStamp = stamp
        performReset(interactive: false)
    }

    private func shouldReset(schedule: ResetSchedule, now: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .weekday, .day], from: now)
        switch schedule {
        case .off:
            return false
        case .daily:
            return components.hour == 0 && components.minute == 0
        case .weekly:
            return components.weekday == 2 && components.hour == 0 && components.minute == 0
        case .monthly:
            return components.day == 1 && components.hour == 0 && components.minute == 0
        case .cron:
            do {
                return try CronExpression(settings.cronExpression).matches(now, calendar: calendar)
            } catch {
                return false
            }
        }
    }

    private func resetStamp(schedule: ResetSchedule, now: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekOfYear, .yearForWeekOfYear], from: now)
        switch schedule {
        case .daily:
            return "daily-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        case .weekly:
            return "weekly-\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
        case .monthly:
            return "monthly-\(components.year ?? 0)-\(components.month ?? 0)"
        case .cron:
            return "cron-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(components.hour ?? 0)-\(components.minute ?? 0)"
        case .off:
            return "off"
        }
    }

    private func setLoading() {
        statusItem.button?.title = " ..."
        summaryItem.title = "Refreshing Bifrost budget..."
        usageItem.title = ""
        updateStaticMenuState()
    }

    private func setError(_ message: String) {
        statusItem.button?.title = " !"
        summaryItem.title = "Bifrost budget unavailable"
        usageItem.title = message
        updateStaticMenuState()
    }

    private func updateMenu(virtualKey: VirtualKey, target: BudgetTarget) {
        let budget = target.budget
        let percentage = budget.maxLimit > 0 ? min(999, (budget.currentUsage / budget.maxLimit) * 100) : 0
        let remaining = max(0, budget.maxLimit - budget.currentUsage)
        statusItem.button?.title = String(format: " %.0f%%", percentage)
        summaryItem.title = "\(virtualKey.name ?? virtualKey.id) / \(target.title)"
        usageItem.title = String(
            format: "$%.2f used / $%.2f limit / $%.2f left",
            budget.currentUsage,
            budget.maxLimit,
            remaining
        )
        updateStaticMenuState()
    }

    private func updateStaticMenuState() {
        raiseDefaultItem.title = String(format: "Raise Budget by $%.2f", settings.defaultRaiseAmount)
        scheduleItem.title = scheduleDescription()
        launchAtLoginItem.state = launchAgentInstalled() ? .on : .off
        rebuildDisplayedBudgetMenu()
        rebuildAddVendorBudgetMenu()
        markScheduleMenu()
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
                item.representedObject = target.key
                item.state = target.key == currentTarget?.key ? .on : .off
                item.target = self
                submenu.addItem(item)
            }
        }
        displayedBudgetMenuItem.submenu = submenu
    }

    private func rebuildAddVendorBudgetMenu() {
        guard let item = menu.items.first(where: { $0.title == "Add Vendor Budget" }) else {
            return
        }
        let submenu = NSMenu()
        let providers = currentVirtualKey?.providerConfigs.map(\.provider).sorted() ?? []
        if providers.isEmpty {
            let empty = NSMenuItem(title: "No providers on this Virtual Key", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for provider in providers {
                let child = NSMenuItem(title: "\(provider)...", action: #selector(addVendorBudget(_:)), keyEquivalent: "")
                child.representedObject = provider
                child.target = self
                submenu.addItem(child)
            }
        }
        item.submenu = submenu
    }

    private func scheduleDescription() -> String {
        switch settings.resetSchedule {
        case .off:
            return "Reset schedule: Off"
        case .daily:
            return "Reset schedule: Daily at 00:00"
        case .weekly:
            return "Reset schedule: Weekly on Monday 00:00"
        case .monthly:
            return "Reset schedule: Monthly on day 1 00:00"
        case .cron:
            return "Reset schedule: \(settings.cronExpression)"
        }
    }

    private func markScheduleMenu() {
        for item in menu.items {
            guard item.title == "Budget Reset Schedule",
                  let submenu = item.submenu else {
                continue
            }
            for child in submenu.items {
                guard let raw = child.representedObject as? String else {
                    child.state = .off
                    continue
                }
                child.state = raw == settings.resetSchedule.rawValue ? .on : .off
            }
        }
    }

    private func setActionsEnabled(_ enabled: Bool) {
        resetItem.isEnabled = enabled
        raiseDefaultItem.isEnabled = enabled
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
            .appendingPathComponent("Library/LaunchAgents/com.local.ai-budget-manager.budgetbar.plist")
    }

    private func installLaunchAgent() throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw BudgetBarError.invalidResponse
        }
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ai-budget-manager")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let payload: [String: Any] = [
            "Label": "com.local.ai-budget-manager.budgetbar",
            "ProgramArguments": [executablePath],
            "EnvironmentVariables": [
                "BIFROST_BASE_URL": settings.baseURL.absoluteString,
                "BIFROST_VIRTUAL_KEY_ID": settings.virtualKeyID,
                "BIFROST_BUDGET_ID": settings.budgetID ?? "",
                "BIFROST_BUDGET_RESET_DURATION": settings.resetDuration ?? "",
                "BIFROST_REFRESH_SECONDS": String(Int(settings.refreshSeconds))
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logDir.appendingPathComponent("budgetbar-launchd.out.log").path,
            "StandardErrorPath": logDir.appendingPathComponent("budgetbar-launchd.err.log").path,
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
