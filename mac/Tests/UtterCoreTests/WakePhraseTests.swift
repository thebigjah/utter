import XCTest
@testable import UtterCore

final class WakePhraseTests: XCTestCase {
    let wake = WakePhrase("Hey Cosmic")

    func testFindsPhraseAndRemainder() {
        XCTAssertEqual(wake.remainder(in: "Hey Cosmic, tell Mom I'll be late."), "tell Mom I'll be late.")
        XCTAssertEqual(wake.remainder(in: "hey cosmic"), "")
        XCTAssertEqual(wake.remainder(in: "Okay. Hey, Cosmic. Send it."), "Send it.")
        XCTAssertEqual(wake.remainder(in: "Hay cosmic what time is it"), "what time is it")
    }

    func testIgnoresOtherSpeech() {
        XCTAssertNil(wake.remainder(in: "The cosmic background radiation"))
        XCTAssertNil(wake.remainder(in: "Hey Cosimo, come here"))
    }

    func testCancelWords() {
        XCTAssertTrue(WakePhrase.isCancel("Never mind."))
        XCTAssertTrue(WakePhrase.isCancel("cancel"))
        XCTAssertFalse(WakePhrase.isCancel("Cancel the meeting tomorrow."))
    }
}
