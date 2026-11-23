import Foundation
import XCTest
@testable import GreatGUI

@MainActor
final class DocsChatTests: XCTestCase {
    func testSendsFollowUpsOnlyToTheSelectedProvider() async throws {
        let chat = DocsChat(run: { provider, body in
            let request = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let history = try XCTUnwrap(request["history"] as? [[String: String]])
            let question = try XCTUnwrap(request["question"] as? String)
            XCTAssertEqual(history.count, question == "Follow-up" ? 2 : 0)
            XCTAssertEqual(request["currentSource"] as? String, question == "Follow-up" ? "standards/testing/" : nil)
            XCTAssertEqual(provider, question == "Cortex question" ? .cortex : .codex)
            return .init(answer: "Answer for \(question)", sources: [
                .init(id: "testing", title: "Testing and QA", path: "standards/testing/")
            ])
        })
        for question in ["First question", "Follow-up", "Cortex question"] {
            if question == "Cortex question" { chat.provider = .cortex }
            chat.draft = question
            chat.submit(currentSource: question == "Follow-up" ? "standards/testing/" : nil)
            for _ in 0..<100 {
                if !chat.asking { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertFalse(chat.asking)
            XCTAssertEqual(chat.messages.last?.text, "Answer for \(question)")
            XCTAssertEqual(chat.messages.last?.sources.first?.id, "testing")
        }
        chat.reset()
        XCTAssertTrue(chat.messages.isEmpty)
    }
}
