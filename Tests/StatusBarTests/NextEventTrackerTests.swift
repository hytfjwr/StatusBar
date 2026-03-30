import Foundation
@testable import StatusBar
import Testing

// MARK: - CalendarEventURLExtractionTests

struct CalendarEventURLExtractionTests {

    @Test
    func extractsURLFromLocation() {
        let url = CalendarEvent.extractURL(from: "https://zoom.us/j/123456")
        #expect(url == URL(string: "https://zoom.us/j/123456"))
    }

    @Test
    func extractsURLFromNotes() {
        let url = CalendarEvent.extractURL(from: nil, "Join at https://meet.google.com/abc-def")
        #expect(url?.absoluteString.contains("meet.google.com") == true)
    }

    @Test
    func prefersLocationOverNotes() {
        let url = CalendarEvent.extractURL(
            from: "https://zoom.us/j/111",
            "https://meet.google.com/222"
        )
        #expect(url == URL(string: "https://zoom.us/j/111"))
    }

    @Test
    func returnsNilForPlainText() {
        let url = CalendarEvent.extractURL(from: "Conference Room A", "Bring laptop")
        #expect(url == nil)
    }

    @Test
    func returnsNilForNilInputs() {
        let url = CalendarEvent.extractURL(from: nil, nil)
        #expect(url == nil)
    }

    @Test
    func returnsNilForEmptyStrings() {
        let url = CalendarEvent.extractURL(from: "", "")
        #expect(url == nil)
    }

    @Test
    func ignoresNonMeetingURLs() {
        let url = CalendarEvent.extractURL(
            from: "https://mycompany.atlassian.net/wiki/spaces/ENG/pages/123",
            "See https://jira.example.com/browse/PROJ-42"
        )
        #expect(url == nil)
    }

    @Test
    func picksMeetingURLOverNonMeetingInSameField() {
        let url = CalendarEvent.extractURL(
            from: "Agenda: https://confluence.example.com/page/1 Join: https://zoom.us/j/999"
        )
        #expect(url == URL(string: "https://zoom.us/j/999"))
    }

    @Test
    func fallsBackToNotesWhenLocationHasNoMeetingURL() {
        let url = CalendarEvent.extractURL(
            from: "Conference Room B",
            "https://teams.microsoft.com/l/meetup-join/abc"
        )
        #expect(url?.host?.contains("teams.microsoft.com") == true)
    }

    @Test
    func matchesSubdomainZoom() {
        let url = CalendarEvent.extractURL(from: "https://us02web.zoom.us/j/456")
        #expect(url?.host == "us02web.zoom.us")
    }

    @Test
    func matchesSubdomainWebex() {
        let url = CalendarEvent.extractURL(from: "https://company.webex.com/meet/user")
        #expect(url?.host == "company.webex.com")
    }

    @Test
    func allowsSlackHuddleURL() {
        let url = CalendarEvent.extractURL(
            from: "https://app.slack.com/huddle/T123/C456"
        )
        #expect(url != nil)
    }

    @Test
    func rejectsSlackNonHuddleURL() {
        let url = CalendarEvent.extractURL(
            from: "https://app.slack.com/client/T123/C456"
        )
        #expect(url == nil)
    }
}

// MARK: - NextEventSelectionTests

struct NextEventSelectionTests {

    private func makeEvent(
        title: String = "Test",
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarColor: nil,
            notes: nil,
            url: nil
        )
    }

    @Test
    func skipsEndedEvents() {
        let now = Date()
        let events = [
            makeEvent(
                title: "Past",
                startDate: now.addingTimeInterval(-3_600),
                endDate: now.addingTimeInterval(-1_800)
            ),
            makeEvent(
                title: "Future",
                startDate: now.addingTimeInterval(1_800),
                endDate: now.addingTimeInterval(3_600)
            ),
        ]

        let result = NextEventTracker.nextEvent(from: events, now: now)
        #expect(result?.title == "Future")
    }

    @Test
    func skipsAllDayEvents() {
        let now = Date()
        let events = [
            makeEvent(
                title: "AllDay",
                startDate: now.addingTimeInterval(-3_600),
                endDate: now.addingTimeInterval(36_000),
                isAllDay: true
            ),
            makeEvent(
                title: "Timed",
                startDate: now.addingTimeInterval(600),
                endDate: now.addingTimeInterval(3_600)
            ),
        ]

        let result = NextEventTracker.nextEvent(from: events, now: now)
        #expect(result?.title == "Timed")
    }

    @Test
    func returnsInProgressEvent() {
        let now = Date()
        let events = [
            makeEvent(
                title: "InProgress",
                startDate: now.addingTimeInterval(-600),
                endDate: now.addingTimeInterval(1_800)
            ),
        ]

        let result = NextEventTracker.nextEvent(from: events, now: now)
        #expect(result?.title == "InProgress")
    }

    @Test
    func returnsNilWhenAllEnded() {
        let now = Date()
        let events = [
            makeEvent(
                title: "Done1",
                startDate: now.addingTimeInterval(-7_200),
                endDate: now.addingTimeInterval(-3_600)
            ),
            makeEvent(
                title: "Done2",
                startDate: now.addingTimeInterval(-3_600),
                endDate: now.addingTimeInterval(-1_800)
            ),
        ]

        let result = NextEventTracker.nextEvent(from: events, now: now)
        #expect(result == nil)
    }

    @Test
    func returnsNilForEmptyList() {
        let result = NextEventTracker.nextEvent(from: [], now: Date())
        #expect(result == nil)
    }

    @Test
    func returnsNilWhenOnlyAllDayEvents() {
        let now = Date()
        let events = [
            makeEvent(
                title: "Holiday",
                startDate: now.addingTimeInterval(-3_600),
                endDate: now.addingTimeInterval(36_000),
                isAllDay: true
            ),
        ]

        let result = NextEventTracker.nextEvent(from: events, now: now)
        #expect(result == nil)
    }
}

// MARK: - RemainingLabelTests

struct RemainingLabelTests {

    @Test
    func nowForNegativeInterval() {
        #expect(NextEventTracker.remainingLabel(for: -60) == "Now")
    }

    @Test
    func nowForZero() {
        #expect(NextEventTracker.remainingLabel(for: 0) == "Now")
    }

    @Test
    func lessThanOneMinute() {
        #expect(NextEventTracker.remainingLabel(for: 30) == "in <1m")
    }

    @Test
    func minutesOnly() {
        #expect(NextEventTracker.remainingLabel(for: 900) == "in 15m")
    }

    @Test
    func hoursOnly() {
        #expect(NextEventTracker.remainingLabel(for: 7_200) == "in 2h")
    }

    @Test
    func hoursAndMinutes() {
        #expect(NextEventTracker.remainingLabel(for: 5_400) == "in 1h 30m")
    }
}
