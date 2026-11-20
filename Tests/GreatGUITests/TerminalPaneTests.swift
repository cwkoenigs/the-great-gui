import AppKit
import XCTest
@testable import GreatGUI

@MainActor
final class TerminalPaneTests: XCTestCase {
    func testFastEchoWaitsForWindowAndKeepsOutput() async {
        let exited = expectation(description: "echo exited")
        let run = AppModel.RunState(name: "tools", run: "echo demo-echo updated", cwd: nil, interactive: true)
        let pane = TerminalPane(run: run, theme: .dark) { code in
            XCTAssertEqual(code, 0)
            exited.fulfill()
        }
        let coordinator = pane.makeCoordinator()
        let terminal = pane.makeTerminal(coordinator: coordinator)
        XCTAssertFalse(terminal.process.running, "The shell must wait for the terminal to be laid out in a window")

        let frame = NSRect(x: 0, y: 0, width: 680, height: 310)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        terminal.frame = frame
        window.contentView = terminal
        await fulfillment(of: [exited], timeout: 5)
        XCTAssertTrue(String(decoding: terminal.getBufferAsData(), as: UTF8.self).contains("demo-echo updated"))
        withExtendedLifetime((window, coordinator)) {}
    }
}
