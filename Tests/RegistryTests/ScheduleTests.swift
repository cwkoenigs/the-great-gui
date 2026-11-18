import XCTest
@testable import Registry

final class ScheduleTests: XCTestCase {
    func testPhrasesParseAndReadBack() throws {
        XCTAssertEqual(try Schedule("every 15m").english, "every 15 minutes")
        XCTAssertEqual(try Schedule("every 1 hour").english, "every hour")
        XCTAssertEqual(try Schedule("Every 2h").kind, .interval(seconds: 7200))
        XCTAssertEqual(try Schedule("hourly").english, "hourly")
        XCTAssertEqual(try Schedule("hourly :15").english, "hourly at :15")
        XCTAssertEqual(try Schedule("daily 09:00").english, "daily at 09:00")
        XCTAssertEqual(try Schedule("weekdays  8:30").english, "weekdays at 08:30")
        XCTAssertEqual(try Schedule("weekends 10:00").english, "weekends at 10:00")
        XCTAssertEqual(try Schedule("mon,thu 18:00").english, "Mon, Thu at 18:00")
        XCTAssertEqual(try Schedule("Monday,friday 18:00").kind, .calendar([.init(minute: 0, hour: 18, weekday: 1), .init(minute: 0, hour: 18, weekday: 5)]))
        XCTAssertEqual(try Schedule("monthly 1 07:00").english, "monthly on the 1st at 07:00")
        XCTAssertEqual(try Schedule("monthly 22 07:00").english, "monthly on the 22nd at 07:00")
        XCTAssertEqual(try Schedule("weekdays 08:30").text, "weekdays 08:30")
    }

    func testBadPhrasesNameTheForms() {
        for bad in ["", "every", "every day", "every 0m", "every 15", "daily", "daily 25:00", "monthly 32 07:00", "mon,xyz 18:00", "soon"] {
            XCTAssertThrowsError(try Schedule(bad), bad) { e in
                let r = e as? RegistryError
                XCTAssertTrue(r?.what.hasPrefix("schedule") ?? false, bad)
                XCTAssertEqual(r?.fix, Schedule.forms, bad)
            }
        }
    }

    func testNextOccurrence() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        // Tuesday 2026-11-10 10:00 local
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10, minute: 0))!
        func comps(_ d: Date?) -> [Int] { let c = cal.dateComponents([.month, .day, .hour, .minute], from: d!); return [c.month!, c.day!, c.hour!, c.minute!] }
        XCTAssertEqual(comps(try Schedule("daily 09:00").next(after: now, calendar: cal)), [11, 11, 9, 0])
        XCTAssertEqual(comps(try Schedule("daily 10:30").next(after: now, calendar: cal)), [11, 10, 10, 30])
        XCTAssertEqual(comps(try Schedule("weekdays 08:30").next(after: now, calendar: cal)), [11, 11, 8, 30])
        XCTAssertEqual(comps(try Schedule("weekends 10:00").next(after: now, calendar: cal)), [11, 14, 10, 0])
        XCTAssertEqual(comps(try Schedule("mon 18:00").next(after: now, calendar: cal)), [11, 16, 18, 0])
        XCTAssertEqual(comps(try Schedule("monthly 1 07:00").next(after: now, calendar: cal)), [12, 1, 7, 0])
        XCTAssertEqual(comps(try Schedule("hourly :15").next(after: now, calendar: cal)), [11, 10, 10, 15])
        XCTAssertNil(try Schedule("every 15m").next(after: now, calendar: cal))
    }

    func testRegistryParsesAndRefusesSchedules() throws {
        let ok = try Registry.parse("""
        [[command]]
        name = "a"
        run = "echo {x}"
        schedule = "weekdays 08:30"
        [[command.param]]
        name = "x"
        default = "1"
        """)
        XCTAssertEqual(ok.commands[0].schedule?.english, "weekdays at 08:30")
        XCTAssertTrue(RegistryWriter.render(ok.commands[0]).contains("schedule = \"weekdays 08:30\""))
        for (toml, what) in [
            ("[[command]]\nname = \"a\"\nrun = \"true\"\nschedule = \"soon\"\n", "a: schedule 'soon' is not understood"),
            ("[[command]]\nname = \"a\"\nrun = \"true\"\ngate = true\nschedule = \"daily 09:00\"\n", "a is gated and scheduled"),
            ("[[command]]\nname = \"a\"\nrun = \"true\"\ninteractive = true\nschedule = \"daily 09:00\"\n", "a is interactive and scheduled"),
            ("[[command]]\nname = \"a\"\nrun = \"echo {x}\"\nschedule = \"daily 09:00\"\n[[command.param]]\nname = \"x\"\n", "a is scheduled but its parameter x has no default"),
        ] {
            XCTAssertThrowsError(try Registry.parse(toml)) { XCTAssertEqual(($0 as? RegistryError)?.what, what) }
        }
        XCTAssertEqual(try RegistryWriter.build(name: "b", run: "true", schedule: " every 5m ").schedule?.text, "every 5m")
    }
}
