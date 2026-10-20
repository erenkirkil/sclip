import Combine
import Foundation
import XCTest

@testable import SclipViewModels

@MainActor
final class SearchViewModelTests: XCTestCase {
    private var bag = Set<AnyCancellable>()

    private func countFocusRequests(_ vm: SearchViewModel) -> Counter {
        let counter = Counter()
        vm.focusRequest.sink { counter.value += 1 }.store(in: &bag)
        return counter
    }

    @MainActor
    private final class Counter { var value = 0 }

    func testStartsClosedWithEmptyQuery() {
        let vm = SearchViewModel()
        XCTAssertFalse(vm.isOpen)
        XCTAssertEqual(vm.query, "")
    }

    func testOpenSetsIsOpenAndKeepsQuery() {
        let vm = SearchViewModel()
        vm.open()
        vm.query = "abc"
        XCTAssertTrue(vm.isOpen)
        XCTAssertEqual(vm.query, "abc")
    }

    /// B-6.2.3: açıkken Cmd+F odak + tümünü seç ister.
    func testCmdFWhenOpenEmitsFocusRequest() {
        let vm = SearchViewModel()
        vm.open()
        let focus = countFocusRequests(vm)
        vm.open()
        XCTAssertEqual(focus.value, 1)
        XCTAssertTrue(vm.isOpen)
        vm.open()
        XCTAssertEqual(focus.value, 2)
    }

    /// Flutter `_openSearch` kapalıyken de odak ister (home_page.dart:463-480); UI odağı buradan alır.
    func testOpenFromClosedAlsoEmitsFocusRequest() {
        let vm = SearchViewModel()
        let focus = countFocusRequests(vm)
        vm.open()
        XCTAssertEqual(focus.value, 1)
        XCTAssertTrue(vm.isOpen)
    }

    func testFocusRequestEmittedAfterStateIsOpen() {
        let vm = SearchViewModel()
        var openAtEmission: Bool?
        vm.focusRequest.sink { openAtEmission = vm.isOpen }.store(in: &bag)
        vm.open()
        XCTAssertEqual(openAtEmission, true)
    }

    func testSearchCloseClearsQuery() {
        let vm = SearchViewModel()
        vm.open()
        vm.query = "abc"
        vm.close()
        XCTAssertFalse(vm.isOpen)
        XCTAssertEqual(vm.query, "")
    }

    func testCloseWhenClosedIsNoOpAndEmitsNothing() {
        let vm = SearchViewModel()
        let focus = countFocusRequests(vm)
        vm.close()
        XCTAssertFalse(vm.isOpen)
        XCTAssertEqual(vm.query, "")
        XCTAssertEqual(focus.value, 0)
    }

    /// B-6.5.2: panel gizlenince yalnız sorgu gider, çubuk açık kalır.
    func testClearQueryKeepsBarOpen() {
        let vm = SearchViewModel()
        vm.open()
        vm.query = "abc"
        vm.clearQuery()
        XCTAssertTrue(vm.isOpen)
        XCTAssertEqual(vm.query, "")
    }

    func testClearQueryDoesNotEmitFocusRequest() {
        let vm = SearchViewModel()
        vm.open()
        vm.query = "abc"
        let focus = countFocusRequests(vm)
        vm.clearQuery()
        XCTAssertEqual(focus.value, 0)
    }
}
