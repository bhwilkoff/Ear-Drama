import Foundation
import Testing

struct AgeGateTests {
    @Test func aYearAloneCountsTheSaferWay() {
        #expect(AgeGate.isUnder13(birthYear: 2013, year: 2026))
        #expect(!AgeGate.isUnder13(birthYear: 2012, year: 2026))
        #expect(AgeGate.isUnder13(birthYear: 2026, year: 2026))
    }

    @Test func theYearsRunBackOneHundredTwenty() {
        let years = AgeGate.years(now: 2026)
        #expect(years.first == 2026)
        #expect(years.count == 120)
        #expect(years.last == 1907)
    }

    @Test func onlyTheBooleanIsKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "AgeGateTests.\(UUID().uuidString)"))
        #expect(AgeGate.stored(defaults) == nil)
        AgeGate.keep(over13: false, defaults)
        #expect(AgeGate.stored(defaults) == false)
        AgeGate.keep(over13: true, defaults)
        #expect(AgeGate.stored(defaults) == true)
    }

    @Test func theSevenRefusalsHaveTheirWords() {
        let words = ["confirmations_required": "Check both boxes first.", "reference_required": "Name the school or district.",
                     "pending_owner_policy": "Not open yet.", "bad_end_date": "That is not a date.",
                     "end_date_past": "Pick a later date.", "end_date_too_far": "Pick an earlier date.",
                     "submitted": "A published play stays."]
        for (code, line) in words { #expect(ReadCore.refusal(code) == line) }
        #expect(PlaysShare.line(PlaysRefusal.code("submitted")) == "A published play stays.")
    }
}
