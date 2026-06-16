import XCTest
@testable import cdt_menubar

/// Covers the plan-tier label mapping — the logic that regressed in 1.22.1 when "Claude Max" was
/// hardcoded. The rule: only ever report the real `subscriptionType` field; never guess a tier.
final class PlanLabelTests: XCTestCase {
    func testMaxWithMultiplier() {
        XCTAssertEqual(planLabel(subscriptionType: "max", rateLimitTier: "default_claude_max_5x"), "Max 5x")
        XCTAssertEqual(planLabel(subscriptionType: "max", rateLimitTier: "default_claude_max_20x"), "Max 20x")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(planLabel(subscriptionType: "MAX", rateLimitTier: "DEFAULT_CLAUDE_MAX_5X"), "Max 5x")
    }

    func testProNoMultiplier() {
        // "default_claude_pro" has no "<n>x" token, so no multiplier is appended.
        XCTAssertEqual(planLabel(subscriptionType: "pro", rateLimitTier: "default_claude_pro"), "Pro")
        XCTAssertEqual(planLabel(subscriptionType: "pro", rateLimitTier: nil), "Pro")
    }

    func testKnownTiersWithoutTier() {
        XCTAssertEqual(planLabel(subscriptionType: "free", rateLimitTier: nil), "Free")
        XCTAssertEqual(planLabel(subscriptionType: "team", rateLimitTier: nil), "Team")
        XCTAssertEqual(planLabel(subscriptionType: "max", rateLimitTier: nil), "Max")
    }

    func testUnknownTierIsTitleCasedVerbatim() {
        XCTAssertEqual(planLabel(subscriptionType: "enterprise", rateLimitTier: nil), "Enterprise")
        XCTAssertEqual(planLabel(subscriptionType: "business", rateLimitTier: nil), "Business")
    }

    func testMissingOrEmptyIsNil() {
        XCTAssertNil(planLabel(subscriptionType: nil, rateLimitTier: nil))
        XCTAssertNil(planLabel(subscriptionType: "", rateLimitTier: "default_claude_max_5x"))
        XCTAssertNil(planLabel(subscriptionType: "   ", rateLimitTier: nil))
    }
}
