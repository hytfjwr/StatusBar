import Combine
import StatusBarKit
import SwiftUI

// MARK: - DateEvent

enum DateEvent {
    static let nextEventChanged = "calendar_next_event_changed"
}

extension IPCEventEnvelope {
    static func calendarNextEventChanged(title: String?, startDate: String?, timeUntilStart: Double?) -> Self {
        var fields: [String: JSONValue] = [:]
        if let title {
            fields["title"] = .string(title)
        }
        if let startDate {
            fields["startDate"] = .string(startDate)
        }
        if let timeUntilStart {
            fields["timeUntilStartSeconds"] = .number(timeUntilStart)
        }
        return IPCEventEnvelope(
            event: DateEvent.nextEventChanged,
            payload: fields.isEmpty ? nil : .object(fields)
        )
    }
}

// MARK: - DateSettings

@MainActor
@Observable
final class DateSettings: WidgetConfigProvider {
    static let shared = DateSettings()

    let configID = "date"
    private var suppressWrite = false

    var format: String {
        didSet { if !suppressWrite {
            WidgetConfigRegistry.shared.notifySettingsChanged()
        } }
    }

    var showNextEventInBar: Bool {
        didSet { if !suppressWrite {
            WidgetConfigRegistry.shared.notifySettingsChanged()
        } }
    }

    var showNextEventInPopup: Bool {
        didSet { if !suppressWrite {
            WidgetConfigRegistry.shared.notifySettingsChanged()
        } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "date")
        format = cfg?["format"]?.stringValue ?? "EEE dd. MMM"
        showNextEventInBar = cfg?["showNextEventInBar"]?.boolValue ?? true
        showNextEventInPopup = cfg?["showNextEventInPopup"]?.boolValue ?? true
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        [
            "format": .string(format),
            "showNextEventInBar": .bool(showNextEventInBar),
            "showNextEventInPopup": .bool(showNextEventInPopup),
        ]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["format"]?.stringValue {
            format = v
        }
        if let v = values["showNextEventInBar"]?.boolValue {
            showNextEventInBar = v
        }
        if let v = values["showNextEventInPopup"]?.boolValue {
            showNextEventInPopup = v
        }
    }
}

// MARK: - DateWidget

@MainActor
@Observable
final class DateWidget: StatusBarWidget, EventEmitting {
    let id = "date"
    let position: WidgetPosition = .right
    let updateInterval: TimeInterval? = 60
    var sfSymbolName: String {
        "calendar"
    }

    private var currentDate = ""
    private var timer: AnyCancellable?
    private let formatter = DateFormatter()

    private var popupPanel: PopupPanel?
    private var calendarService = CalendarService()
    private let isoFormatter = ISO8601DateFormatter()
    private var tracker: NextEventTracker?
    private var nextEvent: CalendarEvent?
    private var timeUntilStart: TimeInterval?
    private var isLoadingEvents = true

    func start() {
        applyFormat()
        updateDate()
        timer = Timer.publish(every: 60, tolerance: 6, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateDate() }
        observeSettings()
        startTrackerIfNeeded()
    }

    func stop() {
        timer?.cancel()
        tracker?.stop()
        popupPanel?.hidePopup()
    }

    private func startTrackerIfNeeded() {
        tracker?.stop()
        tracker = nil
        let settings = DateSettings.shared
        guard settings.showNextEventInBar || settings.showNextEventInPopup else {
            nextEvent = nil
            timeUntilStart = nil
            return
        }
        isLoadingEvents = true
        let t = NextEventTracker()
        t.onUpdate = { [weak self] event, interval in
            let changed = self?.nextEvent?.id != event?.id
            withAnimation(.numericTransition) {
                self?.nextEvent = event
                self?.timeUntilStart = interval
                self?.isLoadingEvents = false
            }
            if changed, let self {
                refreshPopupIfOpen()
                emit(.calendarNextEventChanged(
                    title: event?.title,
                    startDate: event.map { self.isoFormatter.string(from: $0.startDate) },
                    timeUntilStart: interval
                ))
            }
        }
        tracker = t
        Task { await t.start(calendarService: calendarService) }
    }

    var hasSettings: Bool {
        true
    }

    var preferredSettingsSize: CGSize? {
        CGSize(width: 360, height: 380)
    }

    func settingsBody() -> some View {
        DateWidgetSettings()
    }

    private func applyFormat() {
        formatter.dateFormat = DateSettings.shared.format
    }

    private func observeSettings() {
        let settings = DateSettings.shared
        let prevInBar = settings.showNextEventInBar
        let prevInPopup = settings.showNextEventInPopup
        withObservationTracking {
            _ = settings.format
            _ = settings.showNextEventInBar
            _ = settings.showNextEventInPopup
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFormat()
                self?.updateDate()
                if settings.showNextEventInBar != prevInBar
                    || settings.showNextEventInPopup != prevInPopup
                {
                    self?.startTrackerIfNeeded()
                }
                self?.observeSettings()
            }
        }
    }

    private func updateDate() {
        currentDate = formatter.string(from: Date())
    }

    func body() -> some View {
        HStack(spacing: 6) {
            Text(currentDate)
                .font(Theme.smallFont)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: .rect(cornerRadius: 4))
                .contentShape(Rectangle())
                .onTapGesture { [weak self] in
                    self?.togglePopup()
                }

            if DateSettings.shared.showNextEventInBar {
                nextEventPill()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Date")
        .accessibilityValue(nextEventAccessibilityValue)
    }

    @ViewBuilder
    private func nextEventPill() -> some View {
        if let event = nextEvent, let interval = timeUntilStart {
            let label = NextEventTracker.remainingLabel(for: interval)
            HStack(spacing: 4) {
                Text(event.title)
                    .font(Theme.smallFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 140)

                Text(label)
                    .font(Theme.smallFont)
                    .foregroundStyle(interval <= 300 ? Theme.red : Theme.accentBlue)
                    .contentTransition(.numericText())

                if let url = event.url {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentBlue)
                        .contentShape(Circle())
                        .onTapGesture {
                            NSWorkspace.shared.open(url)
                        }
                        .accessibilityLabel("Join \(event.title)")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular, in: .rect(cornerRadius: 4))
        } else if nextEvent == nil, !isLoadingEvents {
            Text("No events today")
                .font(Theme.smallFont)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
    }

    private var nextEventAccessibilityValue: String {
        if let event = nextEvent, let interval = timeUntilStart {
            let label = NextEventTracker.remainingLabel(for: interval)
            return "\(currentDate), \(event.title) \(label)"
        }
        return "\(currentDate), No events today"
    }

    private func togglePopup() {
        if popupPanel?.isVisible == true {
            popupPanel?.hidePopup()
        } else {
            showPopup()
        }
    }

    private func showPopup() {
        if popupPanel == nil {
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame(width: 120) else {
            return
        }

        let popupEvent = DateSettings.shared.showNextEventInPopup ? nextEvent : nil
        let content = CalendarPopupContent(calendarService: calendarService, nextEvent: popupEvent)
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: content)
    }

    private func refreshPopupIfOpen() {
        guard let panel = popupPanel, panel.isVisible else {
            return
        }
        let popupEvent = DateSettings.shared.showNextEventInPopup ? nextEvent : nil
        let content = CalendarPopupContent(calendarService: calendarService, nextEvent: popupEvent)
        panel.updateContent(content)
    }
}

// MARK: - CalendarPopupContent

struct CalendarPopupContent: View {
    let calendarService: CalendarService
    let nextEvent: CalendarEvent?

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var monthEvents: [CalendarEvent] = []
    @State private var events: [CalendarEvent] = []
    @State private var datesWithEvents: Set<DateComponents> = []
    @State private var isLoading = true

    private let calendar = Calendar.current
    private let dayOfWeekSymbols = Calendar.current.veryShortWeekdaySymbols

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let selectedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let nextEvent {
                nextUpSection(event: nextEvent)
                    .padding(12)

                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .padding(.horizontal, 12)
            }

            monthHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            dayOfWeekHeaders
                .padding(.horizontal, 8)

            calendarGrid
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.horizontal, 12)

            eventsSection
                .padding(12)
        }
        .frame(width: 300)
        .task {
            await loadMonthData()
        }
        .onChange(of: selectedDate) {
            if calendar.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) {
                events = calendarService.filterEvents(from: monthEvents, for: selectedDate)
            } else {
                Task { await loadMonthData() }
            }
        }
        .onChange(of: displayedMonth) {
            Task { await loadMonthData() }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.monthYearFormatter.string(from: displayedMonth))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(Self.selectedDateFormatter.string(from: selectedDate))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                if !calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) {
                    Button(action: goToToday) {
                        Text("Today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.accentBlue) // intentional: accent color
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PopupButtonStyle(cornerRadius: 4))
                }

                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PopupButtonStyle(cornerRadius: 4))

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PopupButtonStyle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Day of Week Headers

    private var dayOfWeekHeaders: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(dayOfWeekSymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(height: 20)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = daysInMonth()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { date in
                if let date {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 32)
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let dayNumber = calendar.component(.day, from: date)
        let hasEvents = datesWithEvents.contains(
            calendar.dateComponents([.year, .month, .day], from: date)
        )

        return Button(action: { selectedDate = date }, label: {
            VStack(spacing: 1) {
                Text("\(dayNumber)")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundColor(dayTextColor(isToday: isToday, isSelected: isSelected, isCurrentMonth: isCurrentMonth))

                Circle()
                    .fill(hasEvents && !isSelected ? Theme.accentBlue : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(dayCellBackground(isToday: isToday, isSelected: isSelected))
            )
            .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }

    private func dayTextColor(isToday: Bool, isSelected: Bool, isCurrentMonth: Bool) -> Color {
        if isSelected {
            return .white
        }
        if isToday {
            return Theme.accentBlue
        }
        return isCurrentMonth ? Color(.labelColor) : Theme.tertiary
    }

    private func dayCellBackground(isToday: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return Theme.accentBlue
        }
        if isToday {
            return Theme.accentBlue.opacity(0.15)
        }
        return .clear
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eventsSectionTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(height: 40)
            } else if events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("No Events")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 4) {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.swiftUIColor)
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(event.timeString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.popupItemCornerRadius, style: .continuous)
                .fill(.quaternary)
        )
    }

    // MARK: - Next Up Section

    private func nextUpSection(event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEXT UP")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.swiftUIColor)
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(event.timeString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let url = event.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Join", systemImage: "arrow.up.right.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accentBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PopupButtonStyle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.popupItemCornerRadius, style: .continuous)
                    .fill(.quaternary)
            )
        }
    }

    // MARK: - Helpers

    private var eventsSectionTitle: String {
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        }
        return Self.shortDateFormatter.string(from: selectedDate)
    }

    private func daysInMonth() -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)

        for day in range {
            if let date = calendar.date(bySetting: .day, value: day, of: firstOfMonth) {
                days.append(date)
            }
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func goToToday() {
        displayedMonth = Date()
        selectedDate = Date()
    }

    private func loadMonthData() async {
        isLoading = true
        let data = await calendarService.fetchMonthData(for: displayedMonth, selectedDate: selectedDate)
        monthEvents = data.allEvents
        datesWithEvents = data.datesWithEvents
        events = data.eventsForSelectedDate
        isLoading = false
    }
}
