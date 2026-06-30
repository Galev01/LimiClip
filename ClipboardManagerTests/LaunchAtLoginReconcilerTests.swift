// ClipboardManagerTests/LaunchAtLoginReconcilerTests.swift
import XCTest
import ServiceManagement
@testable import ClipboardManager

final class LaunchAtLoginReconcilerTests: XCTestCase {

    // MARK: - intent == false: never touch the registration

    func testIntentOffAlwaysNoop() {
        for status in [SMAppService.Status.enabled, .notRegistered, .notFound, .requiresApproval] {
            XCTAssertEqual(
                LaunchAtLoginReconciler.action(intent: false, status: status),
                .none,
                "intent off should never act (status: \(status.rawValue))"
            )
        }
    }

    // MARK: - intent == true: act based on status

    func testIntentOnAndEnabledIsNoop() {
        XCTAssertEqual(LaunchAtLoginReconciler.action(intent: true, status: .enabled), .none)
    }

    func testIntentOnButNotRegisteredReRegisters() {
        XCTAssertEqual(LaunchAtLoginReconciler.action(intent: true, status: .notRegistered), .register)
    }

    func testIntentOnButNotFoundReRegisters() {
        XCTAssertEqual(LaunchAtLoginReconciler.action(intent: true, status: .notFound), .register)
    }

    func testIntentOnButRequiresApprovalNeedsApproval() {
        XCTAssertEqual(LaunchAtLoginReconciler.action(intent: true, status: .requiresApproval), .needsApproval)
    }

    // MARK: - Outcome mapping used by the toggle UI

    func testOutcomeMapping() {
        XCTAssertEqual(LaunchAtLogin.outcome(for: .enabled), .enabled)
        XCTAssertEqual(LaunchAtLogin.outcome(for: .requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLogin.outcome(for: .notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLogin.outcome(for: .notFound), .disabled)
    }
}
