import XCTest
@testable import Strand

/// Personal fork, chantier 10 (Élan), PR B: the bundled essentials (`ElanEssentials`) hold what the reading
/// screen needs, in both languages, every section citing a real source; and the reading log.
final class ElanEssentialsTests: XCTestCase {

    func testTheBundledEssentialsAreTheNineOfTheMockupAndValid() {
        let readings = ElanEssentials.bundled
        XCTAssertEqual(readings.map(\.id),
                       ["hrv", "resting_hr", "spo2", "respiratory_rate", "sleep_stages", "sleep_debt", "charge_effort",
                        "deficit", "protein"])
        for reading in readings {
            XCTAssertEqual(ElanEssentials.validationIssues(reading), [], reading.id)
            XCTAssertEqual(reading.sections.count, 3, reading.id)
            XCTAssertFalse(reading.figures.isEmpty, reading.id)
            XCTAssertTrue((2...3).contains(reading.sources.count), reading.id)
        }
        XCTAssertEqual(readings.filter { $0.theme == .heart }.count, 4)
        XCTAssertEqual(readings.filter { $0.theme == .sleep }.count, 3)
        XCTAssertEqual(readings.filter { $0.theme == .nutrition }.count, 2)
    }

    func testTheSourcesAreOnTheReliableHostsOnly() {
        let allowed = ["pubmed.ncbi.nlm.nih.gov", "pmc.ncbi.nlm.nih.gov", "www.ncbi.nlm.nih.gov", "inserm.fr", "www.inserm.fr",
                       "has-sante.fr", "www.has-sante.fr", "anses.fr", "www.anses.fr", "who.int", "www.who.int",
                       "cochranelibrary.com", "www.cochranelibrary.com"]
        for reading in ElanEssentials.bundled {
            for source in reading.sources {
                let host = URL(string: source.url)?.host ?? ""
                XCTAssertTrue(allowed.contains(host) || host.hasSuffix(".nih.gov"), "\(reading.id): \(source.url)")
                XCTAssertEqual(source.host, host, "\(reading.id): the stated host is the URL's")
            }
        }
    }

    func testTheTextsFollowTheLanguage() {
        let text = ElanLocalized(fr: "Bonjour", en: "Hello")
        XCTAssertEqual(text.text(languageCode: "fr"), "Bonjour")
        XCTAssertEqual(text.text(languageCode: "fr-CA"), "Bonjour")
        XCTAssertEqual(text.text(languageCode: "en"), "Hello")
        XCTAssertEqual(text.text(languageCode: "de"), "Hello", "the other languages read the English")
    }

    func testTheThemeFilterKeepsTheFilesOrder() {
        let readings = ElanEssentials.bundled
        let heart = ElanEssentials.essentials(readings, theme: .heart)
        XCTAssertEqual(heart.map(\.id), ["hrv", "resting_hr", "spo2", "respiratory_rate"])
        XCTAssertEqual(ElanEssentials.essentials(readings, theme: nil).count, readings.count)
    }

    func testValidationNamesWhatIsMissing() {
        let broken = ElanReading(id: "x", theme: .heart, minutes: 4, figures: [],
                                 title: ElanLocalized(fr: "", en: "Title"),
                                 points: ElanLocalizedList(fr: ["a", "b"], en: ["a", "b", "c"]),
                                 sections: [ElanReadingSection(heading: ElanLocalized(fr: "h", en: "h"),
                                                               body: ElanLocalized(fr: "b", en: "b"), source: 2)],
                                 tryIt: ElanLocalized(fr: "t", en: "t"),
                                 sources: [ElanReadingSource(title: "s", url: "http://example.org", host: "example.org", year: nil)])
        let issues = ElanEssentials.validationIssues(broken)
        XCTAssertTrue(issues.contains("x: three points"))
        XCTAssertTrue(issues.contains("x: section cites source 2"))
        XCTAssertTrue(issues.contains("x: source without https: http://example.org"))
        XCTAssertTrue(issues.contains("x: an empty text"))
    }

    func testAMalformedFileGivesNoReading() {
        XCTAssertTrue(ElanEssentials.parseEssentials(Data("not json".utf8)).isEmpty)
    }

    func testTheReadLogRemembersOpenedReadings() {
        let name = "ElanEssentialsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        XCTAssertTrue(ElanReadLog.readIds(d).isEmpty)
        ElanReadLog.markRead("hrv", d)
        ElanReadLog.markRead("hrv", d)
        ElanReadLog.markRead("protein", d)
        XCTAssertEqual(ElanReadLog.readIds(d), ["hrv", "protein"])
    }
}
