import XCTest
@testable import BifrostGauge

final class BudgetPayloadBuilderTests: XCTestCase {
    func testPositiveDoubleValidatorAcceptsTrimmedPositiveFiniteNumbers() {
        XCTAssertEqual(NumericInputValidator.positiveDouble(" 12.5 "), 12.5)
        XCTAssertEqual(NumericInputValidator.positiveDouble("1e2"), 100)
    }

    func testPositiveDoubleValidatorRejectsInvalidNonFiniteAndNonPositiveValues() {
        XCTAssertNil(NumericInputValidator.positiveDouble(""))
        XCTAssertNil(NumericInputValidator.positiveDouble("abc"))
        XCTAssertNil(NumericInputValidator.positiveDouble("0"))
        XCTAssertNil(NumericInputValidator.positiveDouble("-1"))
        XCTAssertNil(NumericInputValidator.positiveDouble("nan"))
        XCTAssertNil(NumericInputValidator.positiveDouble("inf"))
        XCTAssertNil(NumericInputValidator.positiveDouble("-inf"))
    }

    func testVirtualKeyTargetsUseDetailBudgetsIncludingModelScopedBudgets() {
        let virtualKey = makeVirtualKey()

        let targets = BudgetPayloadBuilder.virtualKeyTargets(from: virtualKey)

        XCTAssertEqual(targets.map(\.budget.id), ["model-1d", "model-1w"])
        XCTAssertEqual(targets.map(\.budget.resetDuration), ["1d", "1w"])
    }

    func testSetBudgetLimitPayloadUpdatesOnlySelectedBudgetWithoutDuplicateResetDurations() {
        let virtualKey = makeVirtualKey()
        let target = BudgetPayloadBuilder.virtualKeyTargets(from: virtualKey)[0]

        let updates = BudgetPayloadBuilder.virtualKeyLimitUpdates(virtualKey: virtualKey, target: target, maxLimit: 15)

        XCTAssertEqual(updates, [
            BudgetUpdate(maxLimit: 15, resetDuration: "1d"),
            BudgetUpdate(maxLimit: 20, resetDuration: "1w")
        ])
    }

    func testSetBudgetLimitPayloadPreservesOtherVirtualKeyBudgets() {
        let virtualKey = makeVirtualKey()
        let target = BudgetPayloadBuilder.virtualKeyTargets(from: virtualKey)[1]

        let updates = BudgetPayloadBuilder.virtualKeyLimitUpdates(virtualKey: virtualKey, target: target, maxLimit: 25)

        XCTAssertEqual(updates, [
            BudgetUpdate(maxLimit: 10, resetDuration: "1d"),
            BudgetUpdate(maxLimit: 25, resetDuration: "1w")
        ])
    }

    func testResetBudgetUsagePayloadDeduplicatesVirtualKeyBudgets() {
        let duplicateBudget = makeBudget(id: "vk-1d-duplicate", maxLimit: 99, resetDuration: "1d")
        let budgets = BudgetPayloadBuilder.uniqueBudgetsByResetDuration(makeVirtualKey().budgets + [duplicateBudget])

        let updates = BudgetPayloadBuilder.budgetUpdates(from: budgets)

        XCTAssertEqual(updates.filter { $0.resetDuration == "1d" }.count, 1)
    }

    func testSetBudgetResetDurationUpdatesOnlySelectedVirtualKeyBudget() {
        let virtualKey = makeVirtualKey()
        let target = BudgetPayloadBuilder.virtualKeyTargets(from: virtualKey)[0]

        let updates = BudgetPayloadBuilder.virtualKeyResetDurationUpdates(
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
        let target = BudgetPayloadBuilder.virtualKeyTargets(from: virtualKey)[0]

        XCTAssertTrue(BudgetPayloadBuilder.resetDurationConflicts(virtualKey: virtualKey, target: target, resetDuration: "1w"))
        XCTAssertFalse(BudgetPayloadBuilder.resetDurationConflicts(virtualKey: virtualKey, target: target, resetDuration: "1M"))
    }

    func testCalendarAlignedVirtualKeyPayloadPreservesBudgetLimitsAndResetUsageFlag() {
        let updates = BudgetPayloadBuilder.budgetUpdates(from: BudgetPayloadBuilder.virtualKeyTargets(from: makeVirtualKey()).map(\.budget))
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

    func testRefreshedBudgetsUseFetchedLimitUsageAndResetDuration() {
        let existing = [makeBudget(id: "vk-1d", maxLimit: 10, resetDuration: "1d", virtualKeyID: "vk-personal")]
        let fetched = [makeBudget(id: "vk-1d", maxLimit: 15, currentUsage: 6, resetDuration: "1M", virtualKeyID: "vk-personal")]

        let refreshed = BudgetSnapshotMerger.refreshedBudgets(existing: existing, fetched: fetched)

        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(refreshed[0].id, "vk-1d")
        XCTAssertEqual(refreshed[0].maxLimit, 15)
        XCTAssertEqual(refreshed[0].currentUsage, 6)
        XCTAssertEqual(refreshed[0].resetDuration, "1M")
    }

    func testRefreshedBudgetsAppendFetchedOnlyBudgets() {
        let existing = [makeBudget(id: "vk-1d", maxLimit: 10, resetDuration: "1d", virtualKeyID: "vk-personal")]
        let fetched = [
            makeBudget(id: "vk-1d", maxLimit: 15, currentUsage: 6, resetDuration: "1d", virtualKeyID: "vk-personal"),
            makeBudget(id: "vk-1w", maxLimit: 20, currentUsage: 8, resetDuration: "1w", virtualKeyID: "vk-personal")
        ]

        let refreshed = BudgetSnapshotMerger.refreshedBudgets(existing: existing, fetched: fetched)

        XCTAssertEqual(refreshed.map(\.id), ["vk-1d", "vk-1w"])
        XCTAssertEqual(refreshed.map(\.maxLimit), [15, 20])
        XCTAssertEqual(refreshed.map(\.currentUsage), [6, 8])
    }

    func testBudgetsResponseDecodesModelScopedBudgetsWithoutCurrentUsage() throws {
        let data = Data("""
        {
          "budgets": [
            {
              "id": "model-1d",
              "max_limit": 10,
              "reset_duration": "1d",
              "model_config_id": "model-config"
            }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(BudgetsResponse.self, from: data)

        XCTAssertEqual(response.budgets.map(\.id), ["model-1d"])
        XCTAssertEqual(response.budgets[0].modelConfigID, "model-config")
        XCTAssertEqual(response.budgets[0].currentUsage, 0)
    }

    func testRefreshedBudgetsDoNotMatchVirtualKeyBudgetToModelBudgetWithSameResetDuration() {
        let existing = [
            makeBudget(id: nil, maxLimit: 15, resetDuration: "1d", virtualKeyID: "vk-personal", modelConfigID: "model-config")
        ]
        let fetched = [
            makeBudget(id: nil, maxLimit: 10, currentUsage: 4, resetDuration: "1d", virtualKeyID: "vk-personal")
        ]

        let refreshed = BudgetSnapshotMerger.refreshedBudgets(existing: existing, fetched: fetched)

        XCTAssertEqual(refreshed.count, 2)
        XCTAssertEqual(refreshed[0].modelConfigID, "model-config")
        XCTAssertEqual(refreshed[0].maxLimit, 15)
        XCTAssertNil(refreshed[1].modelConfigID)
        XCTAssertEqual(refreshed[1].maxLimit, 10)
        XCTAssertEqual(refreshed[1].currentUsage, 4)
    }

    private func makeVirtualKey() -> VirtualKey {
        VirtualKey(
            id: "vk-personal",
            name: "Personal",
            budgets: [
                makeBudget(id: "model-1d", maxLimit: 10, resetDuration: "1d", modelConfigID: "model-config"),
                makeBudget(id: "model-1w", maxLimit: 20, resetDuration: "1w", modelConfigID: "model-config")
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
        id: String?,
        maxLimit: Double,
        currentUsage: Double = 0,
        resetDuration: String,
        virtualKeyID: String? = nil,
        providerConfigID: Int? = nil,
        modelConfigID: String? = nil
    ) -> Budget {
        Budget(
            id: id,
            maxLimit: maxLimit,
            currentUsage: currentUsage,
            resetDuration: resetDuration,
            lastReset: nil,
            virtualKeyID: virtualKeyID,
            providerConfigID: providerConfigID,
            modelConfigID: modelConfigID
        )
    }
}
