import XCTest
@testable import UtterCore

final class FormatterTests: XCTestCase {
    func testRemovesFillers() {
        XCTAssertEqual(Formatter.format("Um, so I think, uh, we should go."), "So I think, we should go.")
    }

    func testCollapsesStutteredWords() {
        XCTAssertEqual(Formatter.format("I want the the blue one."), "I want the blue one.")
    }

    func testVoiceCommands() {
        XCTAssertEqual(Formatter.format("Hello there. New paragraph. Thanks for coming."), "Hello there.\n\nThanks for coming.")
        XCTAssertEqual(Formatter.format("First item new line second item"), "First item.\nSecond item.")
        XCTAssertEqual(Formatter.format("Ship it Friday\n\nThanks for waiting"), "Ship it Friday.\n\nThanks for waiting.")
    }

    func testDictionaryFixesCasing() {
        let v = Vocabulary(words: ["Purcell Ventures", "GitHub"])
        XCTAssertEqual(Formatter.format("I pushed it to github for purcell ventures.", vocabulary: v),
                       "I pushed it to GitHub for Purcell Ventures.")
    }

    func testReplacementsAndSnippets() {
        let v = Vocabulary(replacements: ["gonna": "going to"], snippets: ["my email": "elijah@example.com"])
        XCTAssertEqual(Formatter.format("I'm gonna send it to my email.", vocabulary: v),
                       "I'm going to send it to elijah@example.com.")
    }

    func testJoinsMidSentence() {
        XCTAssertEqual(Formatter.format("The meeting moved.", before: "Quick update:"), " The meeting moved.")
        XCTAssertEqual(Formatter.format("Tomorrow works.", before: "I think that"), " tomorrow works.")
        XCTAssertEqual(Formatter.format("I agree.", before: "Honestly"), " I agree.")
        XCTAssertEqual(Formatter.format("Sounds good.", before: "Done. "), "Sounds good.")
        XCTAssertEqual(Formatter.format("Sounds good.", before: ""), "Sounds good.")
    }

    func testEmpty() {
        XCTAssertEqual(Formatter.format("  um  "), "")
    }
}
