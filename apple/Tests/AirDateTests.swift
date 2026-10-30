import Foundation
import Testing

// R1: an air date is shown at the precision the catalog has, in the system's long form.

struct AirDateTests {
    private let us = Locale(identifier: "en_US")

    @Test func aFullDateIsTheLongLocalizedForm() {
        #expect(AirDate.display("1947-10-12", locale: us) == "Sunday, October 12, 1947")
        #expect(AirDate.display("1947-10-12", locale: Locale(identifier: "de_DE")) == "Sonntag, 12. Oktober 1947")
    }

    @Test func aYearOrMonthStaysThatPrecise() {
        #expect(AirDate.display("1947", locale: us) == "1947")
        #expect(AirDate.display("1947-10", locale: us) == "October 1947")
    }

    @Test func noDateAndNoSenseAreHonest() {
        #expect(AirDate.display(nil, locale: us) == "Undated")
        #expect(AirDate.display("", locale: us) == "Undated")
        #expect(AirDate.display("1947-13-40", locale: us) == "1947-13-40", "control: a date that is no day is shown as stored, never invented")
        #expect(AirDate.display("circa 1940", locale: us) == "circa 1940")
    }

    @Test func theStoredFormStaysForColumns() {
        #expect(AirDate.stored("1947-10-12") == "1947-10-12")
        #expect(AirDate.stored(nil) == "Undated")
    }
}
