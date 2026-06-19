import XCTest
@testable import BifrostGauge

final class BudgetPayloadBuilderTests: XCTestCase {
    func testCommonTargetsExcludeModelScopedBudgetsWithDuplicateResetDuration() {
        let virtualKey = makeVirtualKey()

        let targets = BudgetPayloadBuilder.commonTargets(from: virtualKey)

        XCTAssertEqual(targets.map(\.budget.id), ["common-1d", "common-1w"])
        XCTAssertEqual(targets.map(\.budget.resetDuration), ["1d", "1w"])
    }

    func testRaiseBudgetPayloadUpdatesOnlySelectedCommonBudgetWithoutDuplicateResetDurations() {
        let virtualKey = makeVirtualKey()
        let target = BudgetPayloadBuilder.commonTargets(from: virtualKey)[0]

        let updates = BudgetPayloadBuilder.commonLimitUpdates(virtualKey: virtualKey, target: target, maxLimit: 15)

        XCTAssertEqual(updates, [
            BudgetUpdate(maxLimit: 15, resetDuration: "1d"),
            BudgetUpdate(maxLimit: 20, resetDuration: "1w")
        ])
    }

    func testSetBudgetLimitPayloadPreservesOtherCommonBudgets() {
        let virtualKey = makeVirtualKey()
        let target = BudgetPayloadBuilder.commonTargets(from: virtualKey)[1]

        let updates = BudgetPayloadBuilder.commonLimitUpdates(virtualKey: virtualKey, target: target, maxLimit: 25)

        XCTAssertEqual(updates, [
            BudgetUpdate(maxLimit: 10, resetDuration: "1d"),
            BudgetUpdate(maxLimit: 25, resetDuration: "1w")
        ])
    }

    func testResetBudgetUsagePayloadDeduplicatesCommonBudgets() {
        let duplicateCommon = makeBudget(id: "common-1d-duplicate", maxLimit: 99, resetDuration: "1d")
        let budgets = BudgetPayloadBuilder.uniqueBudgetsByResetDuration(makeVirtualKey().budgets + [duplicateCommon])

        let updates = BudgetPayloadBuilder.commonUpdates(from: budgets)

        XCTAssertEqual(updates.filter { $0.resetDuration == "1d" }.count, 1)
    }

    func testSetBudgetResetDurationUpdatesOnlySelectedCommonBudget() {
        let virtualKey = makeVirtualKey()
        let target = BudgetPayloadBuilder.commonTargets(from: virtualKey)[0]

        let updates = BudgetPayloadBuilder.commonResetDurationUpdates(
            virtualKey: virtualKey,
            target: target,
            resetDuration: "1M"
        )

        XCTAssertEqual(updates, [
            BudgetUpdate(maxLimit: 10, resetDuration: "1M"),
            BudgetUpdate(maxLimit: 20, resetDuration: "1w")
        ])
    }

    func testSetBudgetResetDurationDetectsDuplicateTargetWindow() {
        let virtualKey = makeVirtualKey()
        let target = BudgetPayloadBuilder.commonTargets(from: virtualKey)[0]

        XCTAssertTrue(BudgetPayloadBuilder.resetDurationConflicts(virtualKey: virtualKey, target: target, resetDuration: "1w"))
        XCTAssertFalse(BudgetPayloadBuilder.resetDurationConflicts(virtualKey: virtualKey, target: target, resetDuration: "1M"))
    }

    func testCalendarAlignedCommonPayloadPreservesBudgetLimitsAndResetUsageFlag() {
        let updates = BudgetPayloadBuilder.commonUpdates(from: BudgetPayloadBuilder.commonTargets(from: makeVirtualKey()).map(\.budget))
        let payload = BudgetUpdatePayload(budgets: updates, resetBudgetUsage: false, calendarAligned: true)

        XCTAssertEqual(payload.budgets, [
            BudgetUpdate(maxLimit: 10, resetDuration: "1d"),
            BudgetUpdate(maxLimit: 20, resetDuration: "1w")
        ])
        XCTAssertFalse(payload.resetBudgetUsage)
        XCTAssertEqual(payload.calendarAligned, true)
    }

    func testAddVendorBudgetUpdatesExistingProviderBudget() {
        let virtualKey = makeVirtualKey()

        let updates = BudgetPayloadBuilder.providerConfigUpdates(virtualKey: virtualKey, provider: "openai") { budgets in
            BudgetPayloadBuilder.providerBudgetUpdates(budgets: budgets, maxLimit: 7, resetDuration: "1d")
        }

        XCTAssertEqual(updates[0].budgets, [BudgetUpdate(maxLimit: 7, resetDuration: "1d")])
        XCTAssertEqual(updates[1].budgets, [BudgetUpdate(maxLimit: 3, resetDuration: "1d")])
    }

    func testAddVendorBudgetAppendsMissingProviderBudgetAndPreservesKeyIDs() {
        let virtualKey = makeVirtualKey()

        let updates = BudgetPayloadBuilder.providerConfigUpdates(virtualKey: virtualKey, provider: "openai") { budgets in
            BudgetPayloadBuilder.providerBudgetUpdates(budgets: budgets, maxLimit: 30, resetDuration: "1M")
        }

        XCTAssertEqual(updates[0].keyIDs, ["*"])
        XCTAssertEqual(updates[0].budgets, [
            BudgetUpdate(maxLimit: 5, resetDuration: "1d"),
            BudgetUpdate(maxLimit: 30, resetDuration: "1M")
        ])
        XCTAssertEqual(updates[1].keyIDs, ["anthropic-key"])
    }

    private func makeVirtualKey() -> VirtualKey {
        VirtualKey(
            id: "vk-personal",
            name: "Personal",
            budgets: [
                makeBudget(id: "model-1d", maxLimit: 5, resetDuration: "1d", modelConfigID: "model-config"),
                makeBudget(id: "common-1d", maxLimit: 10, resetDuration: "1d", virtualKeyID: "vk-personal"),
                makeBudget(id: "provider-leaked-1d", maxLimit: 3, resetDuration: "1d", providerConfigID: 2),
                makeBudget(id: "common-1w", maxLimit: 20, resetDuration: "1w", virtualKeyID: "vk-personal")
            ],
            providerConfigs: [
                ProviderConfig(
                    id: 1,
                    provider: "openai",
                    weight: 1,
                    allowedModels: ["*"],
                    blacklistedModels: [],
                    allowAllKeys: true,
                    keys: [],
                    budgets: [makeBudget(id: "openai-1d", maxLimit: 5, resetDuration: "1d", providerConfigID: 1)]
                ),
                ProviderConfig(
                    id: 2,
                    provider: "anthropic",
                    weight: 1,
                    allowedModels: ["*"],
                    blacklistedModels: [],
                    allowAllKeys: false,
                    keys: [DBKey(keyID: "anthropic-key")],
                    budgets: [makeBudget(id: "anthropic-1d", maxLimit: 3, resetDuration: "1d", providerConfigID: 2)]
                )
            ],
            calendarAligned: false
        )
    }

    private func makeBudget(
        id: String,
        maxLimit: Double,
        resetDuration: String,
        virtualKeyID: String? = nil,
        providerConfigID: Int? = nil,
        modelConfigID: String? = nil
    ) -> Budget {
        Budget(
            id: id,
            maxLimit: maxLimit,
            currentUsage: 0,
            resetDuration: resetDuration,
            lastReset: nil,
            virtualKeyID: virtualKeyID,
            providerConfigID: providerConfigID,
            modelConfigID: modelConfigID
        )
    }
}
