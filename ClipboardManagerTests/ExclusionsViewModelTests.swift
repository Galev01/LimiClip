// ClipboardManagerTests/ExclusionsViewModelTests.swift
import XCTest
@testable import ClipboardManager

@MainActor
final class ExclusionsViewModelTests: XCTestCase {

    private func makeStore() throws -> ClipboardStore {
        try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    }

    // MARK: - init

    func testInitLoadsExistingExclusions() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.example.app", name: "Example App")
        let vm = ExclusionsViewModel(store: store)
        XCTAssertEqual(vm.exclusions.count, 1)
        XCTAssertEqual(vm.exclusions[0].bundleId, "com.example.app")
        XCTAssertEqual(vm.exclusions[0].name, "Example App")
    }

    func testInitWithEmptyStoreProducesEmptyList() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        XCTAssertTrue(vm.exclusions.isEmpty)
    }

    // MARK: - add

    func testAddExclusionAppearsInList() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        XCTAssertTrue(vm.exclusions.isEmpty)
        vm.add(bundleId: "com.test.browser", name: "Test Browser")
        XCTAssertEqual(vm.exclusions.count, 1)
        XCTAssertEqual(vm.exclusions[0].bundleId, "com.test.browser")
    }

    func testAddDuplicateBundleIdIsIdempotent() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        vm.add(bundleId: "com.dupe", name: "Dupe App")
        vm.add(bundleId: "com.dupe", name: "Dupe App")
        XCTAssertEqual(vm.exclusions.count, 1)
    }

    // MARK: - remove

    func testRemoveExclusionDisappearsFromList() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.to.remove", name: "To Remove")
        let vm = ExclusionsViewModel(store: store)
        XCTAssertEqual(vm.exclusions.count, 1)
        vm.remove(bundleId: "com.to.remove")
        XCTAssertTrue(vm.exclusions.isEmpty)
    }

    func testRemoveNonExistentBundleIdIsNoOp() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.kept", name: "Kept")
        let vm = ExclusionsViewModel(store: store)
        vm.remove(bundleId: "com.does.not.exist")
        XCTAssertEqual(vm.exclusions.count, 1)
    }

    // MARK: - sorted order

    func testExclusionsAreSortedByName() throws {
        let store = try makeStore()
        try store.addExclusion(bundleId: "com.z", name: "Zebra")
        try store.addExclusion(bundleId: "com.a", name: "Apple")
        try store.addExclusion(bundleId: "com.m", name: "Mango")
        let vm = ExclusionsViewModel(store: store)
        XCTAssertEqual(vm.exclusions.map(\.name), ["Apple", "Mango", "Zebra"])
    }

    // MARK: - notification reload

    func testStoreDidChangeNotificationReloadsExclusions() throws {
        let store = try makeStore()
        let vm = ExclusionsViewModel(store: store)
        XCTAssertTrue(vm.exclusions.isEmpty)

        // Add via store directly (bypasses vm), then fire the notification manually.
        try store.addExclusion(bundleId: "com.notified", name: "Notified App")
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)

        XCTAssertEqual(vm.exclusions.count, 1)
        XCTAssertEqual(vm.exclusions[0].name, "Notified App")
    }
}
