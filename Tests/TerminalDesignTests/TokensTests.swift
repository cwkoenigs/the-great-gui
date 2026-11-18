import SwiftUI
import XCTest
@testable import TerminalDesign

final class TokensTests: XCTestCase {
    func testEveryRoleHasBothSchemes() {
        for role in Tokens.Role.allCases {
            XCTAssertNotNil(Tokens.dark[role], "\(role) missing in dark")
            XCTAssertNotNil(Tokens.light[role], "\(role) missing in light")
            XCTAssertEqual(Tokens.dark[role]?.count, 7, "\(role) dark is not #rrggbb")
            XCTAssertEqual(Tokens.light[role]?.count, 7, "\(role) light is not #rrggbb")
        }
    }

    func testSemanticAliasesNameRoles() {
        XCTAssertEqual(Tokens.Semantic.voiceYou, .strong)
        XCTAssertEqual(Tokens.Semantic.voiceAgent, .accent)
        XCTAssertEqual(Tokens.Semantic.edgeApproval, .warn)
        XCTAssertEqual(Tokens.Semantic.bandBg, .brand)
    }

    func testMascotGridIsTheDocumentedSize() {
        XCTAssertEqual(Tokens.Mascot.grid.count, Tokens.Mascot.height)
        for row in Tokens.Mascot.grid { XCTAssertEqual(row.count, Tokens.Mascot.width) }
        XCTAssertEqual(Set(Tokens.Mascot.legend.keys), Set("DCk."))
    }

    func testGlyphsAreSingleCells() {
        let g_ = Tokens.Glyph.self
        for g in [g_.prompt, g_.agent, g_.run, g_.result, g_.rail, g_.close, g_.ok, g_.warn, g_.err, g_.select, g_.fold] + g_.spinner {
            XCTAssertEqual(g.count, 1, "\(g) is not one cell")
        }
    }

    func testHexParsesAndBadHexIsLoud() {
        XCTAssertEqual(Color(hex: "#1d1f20"), Color(red: 0x1d / 255.0, green: 0x1f / 255.0, blue: 0x20 / 255.0))
        XCTAssertEqual(Color(hex: "nope"), Color(red: 1, green: 0, blue: 1))
    }
}
