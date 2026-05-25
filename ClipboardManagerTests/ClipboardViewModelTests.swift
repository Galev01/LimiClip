import XCTest
@testable import ClipboardManager

@MainActor
final class ClipboardViewModelTests: XCTestCase {

    private func makeStore() throws -> ClipboardStore {
        try ClipboardStore(configuration: ClipboardStore.testingConfiguration())
    }

    func testFilteredItemsIncludesAllByDefault() throws {
        let store = try makeStore()
        _ = try store.recordText("hello", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("world", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        XCTAssertEqual(vm.filteredItems.count, 2)
        XCTAssertEqual(vm.selectedTab, .all)
    }

    func testTabFiltersByKind() throws {
        let store = try makeStore()
        _ = try store.recordText("text item", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordImage(
            contentHash: "img-hash", blobPath: "aa/bb/x.png",
            dimensions: .init(width: 10, height: 10), byteSize: 100,
            sourceApp: nil, sourceBundleId: nil
        )
        let ref = FileReference(path: "/x/y.pdf", name: "y.pdf", byteSize: 1, modifiedAt: 1)
        _ = try store.recordFile(reference: ref, sourceApp: nil, sourceBundleId: nil)

        let vm = ClipboardViewModel(store: store)

        vm.selectedTab = .text
        XCTAssertEqual(vm.filteredItems.map(\.body), ["text item"])

        vm.selectedTab = .images
        XCTAssertEqual(vm.filteredItems.first?.kind, "image")
        XCTAssertEqual(vm.filteredItems.count, 1)

        vm.selectedTab = .files
        XCTAssertEqual(vm.filteredItems.first?.kind, "file")
        XCTAssertEqual(vm.filteredItems.count, 1)

        vm.selectedTab = .all
        XCTAssertEqual(vm.filteredItems.count, 3)
    }

    func testPinnedTabIsEmptyForNowButSelectable() throws {
        let store = try makeStore()
        _ = try store.recordText("not pinned", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.selectedTab = .pinned
        XCTAssertEqual(vm.filteredItems.count, 0)
    }

    func testSearchFiltersAcrossFields() throws {
        let store = try makeStore()
        _ = try store.recordText("Hello World", sourceApp: "Messages", sourceBundleId: nil)
        _ = try store.recordText("greetings, friend", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.searchQuery = "hello"
        XCTAssertEqual(vm.filteredItems.map(\.body), ["Hello World"])
        vm.searchQuery = "FRIEND"
        XCTAssertEqual(vm.filteredItems.count, 1)
        vm.searchQuery = ""
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    func testFocusedIndexClampsToBounds() throws {
        let store = try makeStore()
        _ = try store.recordText("one", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("two", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("three", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        XCTAssertEqual(vm.focusedIndex, 0)
        vm.moveFocus(by: +1)
        XCTAssertEqual(vm.focusedIndex, 1)
        vm.moveFocus(by: +10)
        XCTAssertEqual(vm.focusedIndex, 2)
        vm.moveFocus(by: -100)
        XCTAssertEqual(vm.focusedIndex, 0)
    }

    func testJumpToIndexClampsAndIgnoresOutOfRange() throws {
        let store = try makeStore()
        _ = try store.recordText("a", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("b", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.jumpTo(index: 5)
        XCTAssertEqual(vm.focusedIndex, 1)
        vm.jumpTo(index: -3)
        XCTAssertEqual(vm.focusedIndex, 0)
    }

    func testTabOrSearchChangeResetsFocus() throws {
        let store = try makeStore()
        _ = try store.recordText("x", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("y", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        vm.moveFocus(by: 1)
        XCTAssertEqual(vm.focusedIndex, 1)
        vm.selectedTab = .text
        XCTAssertEqual(vm.focusedIndex, 0)
        vm.moveFocus(by: 1)
        vm.searchQuery = "x"
        XCTAssertEqual(vm.focusedIndex, 0)
    }

    func testCurrentItemReturnsFocusedOrNil() throws {
        let store = try makeStore()
        _ = try store.recordText("alpha", sourceApp: nil, sourceBundleId: nil)
        _ = try store.recordText("beta", sourceApp: nil, sourceBundleId: nil)
        let vm = ClipboardViewModel(store: store)
        XCTAssertEqual(vm.currentItem?.body, "beta")  // newest first
        vm.moveFocus(by: 1)
        XCTAssertEqual(vm.currentItem?.body, "alpha")
        vm.searchQuery = "zzz"
        XCTAssertNil(vm.currentItem)
    }
}
