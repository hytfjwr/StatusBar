@preconcurrency import EventKit
import Foundation
import StatusBarKit
import SwiftUI

// MARK: - CalendarService

/// Wraps EventKit to fetch calendar events with proper authorization handling.
@MainActor
final class CalendarService {
    private let store = EKEventStore()
    private var accessGranted = false

    /// Request calendar access (cached after first grant).
    func requestAccess() async -> Bool {
        if accessGranted {
            return true
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            accessGranted = true
            return true
        }
        do {
            accessGranted = try await store.requestFullAccessToEvents()
            return accessGranted
        } catch {
            return false
        }
    }

    /// Fetch events for a given date range.
    func fetchEvents(from startDate: Date, to endDate: Date) async -> [CalendarEvent] {
        let granted = await requestAccess()
        guard granted else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                title: event.title ?? "(No Title)",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarColor: event.calendar.color
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    /// Fetch all month events and derive both the date-dot set and the selected day's events.
    func fetchMonthData(for month: Date, selectedDate: Date) async -> MonthData {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)
        else {
            return MonthData(allEvents: [], datesWithEvents: [], eventsForSelectedDate: [])
        }

        let allEvents = await fetchEvents(from: startOfMonth, to: endOfMonth)

        var dates = Set<DateComponents>()
        for event in allEvents {
            var current = calendar.startOfDay(for: max(event.startDate, startOfMonth))
            let end = min(event.endDate, endOfMonth)
            while current < end {
                dates.insert(calendar.dateComponents([.year, .month, .day], from: current))
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                    break
                }
                current = next
            }
        }

        let dayEvents = filterEvents(from: allEvents, for: selectedDate)
        return MonthData(allEvents: allEvents, datesWithEvents: dates, eventsForSelectedDate: dayEvents)
    }

    /// Filter events for a specific day from a pre-fetched event list.
    func filterEvents(from allEvents: [CalendarEvent], for date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        return allEvents.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
    }
}

// MARK: - MonthData

/// Combined result from a month data fetch.
struct MonthData {
    let allEvents: [CalendarEvent]
    let datesWithEvents: Set<DateComponents>
    let eventsForSelectedDate: [CalendarEvent]
}

// MARK: - CalendarEvent

/// A simplified calendar event model.
struct CalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: NSColor?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var timeString: String {
        if isAllDay {
            return "All Day"
        }
        let start = Self.timeFormatter.string(from: startDate)
        let end = Self.timeFormatter.string(from: endDate)
        return "\(start) – \(end)"
    }

    @MainActor var swiftUIColor: Color {
        if let nsColor = calendarColor {
            return Color(nsColor: nsColor)
        }
        return Theme.accentBlue
    }
}
