import Combine
@preconcurrency import EventKit
import Foundation

// MARK: - NextEventTracker

/// Tracks the next upcoming calendar event for today, with adaptive polling.
/// Polls every 60s normally, switching to 30s when an event starts within 15 minutes.
@MainActor
final class NextEventTracker {
    var onUpdate: ((_ nextEvent: CalendarEvent?, _ timeUntilStart: TimeInterval?, _ upcoming: [CalendarEvent]) -> Void)?

    private var todayEvents: [CalendarEvent] = []
    private var timer: AnyCancellable?
    private var midnightTask: Task<Void, Never>?
    private var storeObserver: NSObjectProtocol?
    private var storeChangeTask: Task<Void, Never>?
    private weak var calendarService: CalendarService?

    func start(calendarService: CalendarService) async {
        self.calendarService = calendarService
        todayEvents = await calendarService.fetchTodayEvents()
        tick()
        observeStoreChanges()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        midnightTask?.cancel()
        midnightTask = nil
        storeChangeTask?.cancel()
        storeChangeTask = nil
        if let observer = storeObserver {
            NotificationCenter.default.removeObserver(observer)
            storeObserver = nil
        }
    }

    // MARK: - Core Logic

    /// Selects the next non-ended, non-allDay event from today's list.
    nonisolated static func nextEvent(from events: [CalendarEvent], now: Date = Date()) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.endDate > now }
    }

    /// Returns all non-allDay events that haven't started yet.
    nonisolated static func upcomingEvents(from events: [CalendarEvent], now: Date = Date()) -> [CalendarEvent] {
        events.filter { !$0.isAllDay && $0.startDate > now }
    }

    private func tick() {
        let now = Date()
        let event = Self.nextEvent(from: todayEvents, now: now)
        let timeUntilStart = event.map { $0.startDate.timeIntervalSince(now) }
        let upcoming = Self.upcomingEvents(from: todayEvents, now: now)
        onUpdate?(event, timeUntilStart, upcoming)
        scheduleTimer(timeUntilStart: timeUntilStart)
        scheduleMidnightRefresh()
    }

    private func scheduleTimer(timeUntilStart: TimeInterval?) {
        timer?.cancel()

        // If no more events today, no need to poll
        guard timeUntilStart != nil else {
            return
        }

        // Poll faster when an event is approaching (within 15 minutes)
        let interval: TimeInterval = if let t = timeUntilStart, t > 0, t <= 900 {
            30
        } else {
            60
        }

        timer = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func scheduleMidnightRefresh() {
        guard midnightTask == nil else {
            return
        }

        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else {
            return
        }
        let delay = tomorrow.timeIntervalSinceNow + 1

        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            guard let self, let service = calendarService else {
                return
            }
            midnightTask = nil
            todayEvents = await service.fetchTodayEvents()
            tick()
        }
    }

    private func observeStoreChanges() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.debouncedRefresh()
            }
        }
    }

    private func debouncedRefresh() {
        storeChangeTask?.cancel()
        storeChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else {
                return
            }
            guard let self, let service = calendarService else {
                return
            }
            todayEvents = await service.fetchTodayEvents()
            tick()
        }
    }
}

// MARK: - Remaining Time Formatting

extension NextEventTracker {
    /// Formats the remaining time until an event as a human-readable string.
    nonisolated static func remainingLabel(for interval: TimeInterval) -> String {
        if interval <= 0 {
            return "Now"
        }
        if interval < 60 {
            return "in <1m"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "in \(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "in \(hours)h"
        }
        return "in \(hours)h \(remainingMinutes)m"
    }
}
