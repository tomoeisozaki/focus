// Focus: a small Pomodoro timer for the macOS menu bar.
// Logs focus time per category so you can see where your week went.
// MIT License. See LICENSE.

import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case indonesian = "id"
    case english = "en"

    var id: String { rawValue }

    /// The language actually used for text. `system` follows macOS.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let pref = Locale.preferredLanguages.first ?? "en"
        return (pref.hasPrefix("id") || pref.hasPrefix("in")) ? .indonesian : .english
    }

    var pickerLabel: String {
        switch self {
        case .system: return "System / Sistem"
        case .indonesian: return "Bahasa Indonesia"
        case .english: return "English"
        }
    }
}

// MARK: - Categories, phases, status

enum Category: String, CaseIterable, Identifiable {
    case technical, people, strategy, finance

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .technical: return .orange
        case .people: return .green
        case .strategy: return .blue
        case .finance: return .purple
        }
    }

    func name(_ lang: AppLanguage) -> String {
        let isID = lang == .indonesian
        switch self {
        case .technical: return isID ? "Teknis" : "Technical"
        case .people: return isID ? "Orang/Tim" : "People & team"
        case .strategy: return isID ? "Strategi & R&D" : "Strategy & R&D"
        case .finance: return isID ? "Keuangan & Penjualan" : "Finance & sales"
        }
    }

    /// Accepts the stable key and the names used by version 1.0 logs.
    static func parse(_ s: String) -> Category? {
        if let c = Category(rawValue: s) { return c }
        switch s {
        case "Teknis": return .technical
        case "Orang/Tim": return .people
        case "Strategi & R&D": return .strategy
        case "Keuangan & Penjualan": return .finance
        default: return nil
        }
    }
}

enum SessionStatus: String {
    case completed, stopped, manual

    static func parse(_ s: String) -> SessionStatus? {
        if let v = SessionStatus(rawValue: s) { return v }
        switch s {
        case "tuntas": return .completed
        case "dihentikan": return .stopped
        default: return nil
        }
    }
}

enum Phase {
    case idle, focus, shortBreak, longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    func title(_ lang: AppLanguage) -> String {
        let isID = lang == .indonesian
        switch self {
        case .idle: return isID ? "Siap fokus" : "Ready to focus"
        case .focus: return isID ? "Fokus" : "Focus"
        case .shortBreak: return isID ? "Istirahat" : "Break"
        case .longBreak: return isID ? "Istirahat panjang" : "Long break"
        }
    }
}

struct SessionRecord {
    let start: Date
    let end: Date
    let minutes: Double
    let category: Category
    let note: String
    let status: SessionStatus
}

// MARK: - CSV log

final class SessionLog {
    let url: URL

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Focus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("sessions.csv")
        // Version 1.0.0 builds named "Fokus" kept the log in Fokus/sesi.csv. Move it over once.
        let legacy = base.appendingPathComponent("Fokus/sesi.csv")
        if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "start,end,minutes,category,note,status\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func append(_ r: SessionRecord) {
        let note = r.note.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\n", with: " ")
        let line = "\(iso.string(from: r.start)),\(iso.string(from: r.end)),\(String(format: "%.1f", r.minutes)),\(r.category.rawValue),\"\(note)\",\(r.status.rawValue)\n"
        guard let data = line.data(using: .utf8), let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: data)
    }

    func readAll() -> [SessionRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [SessionRecord] = []
        for line in text.split(separator: "\n").dropFirst() {
            let f = SessionLog.parse(String(line))
            guard f.count >= 6,
                  let s = iso.date(from: f[0]), let e = iso.date(from: f[1]),
                  let m = Double(f[2]), let c = Category.parse(f[3]),
                  let st = SessionStatus.parse(f[5]) else { continue }
            out.append(SessionRecord(start: s, end: e, minutes: m, category: c, note: f[4], status: st))
        }
        return out
    }

    static func parse(_ line: String) -> [String] {
        var fields: [String] = []
        var cur = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { inQuotes = false }
                } else { cur.append(c) }
            } else {
                if c == "," { fields.append(cur); cur = "" }
                else if c == "\"" { inQuotes = true }
                else { cur.append(c) }
            }
            i += 1
        }
        fields.append(cur)
        return fields
    }
}

// MARK: - Notifications

enum Notifier {
    static func send(title: String, body: String) {
        NSSound(named: NSSound.Name("Glass"))?.play()
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

// MARK: - Timer

@MainActor
final class FocusTimer: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var remaining: TimeInterval = 0
    @Published var isPaused = false
    @Published var note = ""
    @Published var category: Category { didSet { defaults.set(category.rawValue, forKey: "category") } }
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes") } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    @Published var sessionsBeforeLong: Int { didSet { defaults.set(sessionsBeforeLong, forKey: "sessionsBeforeLong") } }
    @Published var targetEnabled: Bool { didSet { defaults.set(targetEnabled, forKey: "targetEnabled") } }
    @Published var targetPercent: Int { didSet { defaults.set(targetPercent, forKey: "targetPercent") } }
    @Published private(set) var weekMinutes: [Category: Double] = [:]
    @Published private(set) var todayCount = 0

    private let defaults = UserDefaults.standard
    let log = SessionLog()
    private var phaseEnd: Date?
    private var phaseDuration: TimeInterval = 1
    private var focusStartedAt: Date?
    private var focusInCycle = 0
    private var ticker: Timer?

    init() {
        let d = UserDefaults.standard
        category = Category.parse(d.string(forKey: "category") ?? "") ?? .strategy
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        focusMinutes = d.object(forKey: "focusMinutes") as? Int ?? 45
        shortBreakMinutes = d.object(forKey: "shortBreakMinutes") as? Int ?? 10
        longBreakMinutes = d.object(forKey: "longBreakMinutes") as? Int ?? 20
        sessionsBeforeLong = d.object(forKey: "sessionsBeforeLong") as? Int ?? 3
        targetEnabled = d.object(forKey: "targetEnabled") as? Bool ?? false
        targetPercent = d.object(forKey: "targetPercent") as? Int ?? 50
        refreshStats()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    // MARK: Text

    var lang: AppLanguage { language.resolved }

    /// Returns the Indonesian or English string for the current language.
    func tr(_ indonesian: String, _ english: String) -> String {
        lang == .indonesian ? indonesian : english
    }

    func formatMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)\(tr("j", "h")) \(m % 60)m" : "\(m)m"
    }

    // MARK: Display

    var progress: Double { phase == .idle ? 0 : min(1, max(0, 1 - remaining / phaseDuration)) }

    var timeString: String {
        let total = Int((phase == .idle ? Double(focusMinutes * 60) : remaining).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    var menuTitle: String {
        if isPaused { return "\(tr("Jeda", "Paused")) \(timeString)" }
        return phase.isBreak ? "\(tr("Rehat", "Break")) \(timeString)" : timeString
    }

    // MARK: Controls

    func startFocus() {
        begin(.focus, minutes: focusMinutes)
        focusStartedAt = Date()
    }

    private func begin(_ p: Phase, minutes: Int) {
        phase = p
        phaseDuration = TimeInterval(max(1, minutes) * 60)
        remaining = phaseDuration
        phaseEnd = Date().addingTimeInterval(phaseDuration)
        isPaused = false
    }

    func pause() {
        guard let end = phaseEnd else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        phaseEnd = nil
        isPaused = true
    }

    func resume() {
        phaseEnd = Date().addingTimeInterval(remaining)
        isPaused = false
    }

    /// Ends a focus session early. Sessions of a minute or more are still logged.
    func finishFocusEarly() {
        guard phase == .focus else { return }
        if !isPaused, let end = phaseEnd { remaining = max(0, end.timeIntervalSinceNow) }
        let elapsed = phaseDuration - remaining
        if elapsed >= 60 { record(minutes: elapsed / 60, status: .stopped) }
        reset()
    }

    func skipBreak() { reset() }

    private func reset() {
        phase = .idle
        phaseEnd = nil
        isPaused = false
        remaining = 0
        focusStartedAt = nil
    }

    private func tick() {
        guard !isPaused, let end = phaseEnd else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { phaseCompleted() }
    }

    private func phaseCompleted() {
        phaseEnd = nil
        switch phase {
        case .focus:
            record(minutes: phaseDuration / 60, status: .completed)
            focusInCycle += 1
            let long = focusInCycle >= max(1, sessionsBeforeLong)
            if long { focusInCycle = 0 }
            let mins = long ? longBreakMinutes : shortBreakMinutes
            Notifier.send(title: tr("Sesi fokus selesai", "Focus session done"),
                          body: tr("Waktunya istirahat \(mins) menit. Jauhkan layar sebentar.",
                                   "Time for a \(mins)-minute break. Step away from the screen."))
            begin(long ? .longBreak : .shortBreak, minutes: mins)
        case .shortBreak, .longBreak:
            Notifier.send(title: tr("Istirahat selesai", "Break is over"),
                          body: tr("Siap untuk sesi fokus berikutnya?", "Ready for the next focus session?"))
            reset()
        case .idle:
            break
        }
    }

    // MARK: Logging

    private func record(minutes: Double, status: SessionStatus) {
        let end = Date()
        let start = focusStartedAt ?? end.addingTimeInterval(-minutes * 60)
        log.append(SessionRecord(start: start, end: end, minutes: minutes, category: category,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines), status: status))
        refreshStats()
    }

    func logManual(minutes: Int) {
        let end = Date()
        log.append(SessionRecord(start: end.addingTimeInterval(TimeInterval(-minutes * 60)), end: end,
                                 minutes: Double(minutes), category: category,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines), status: .manual))
        refreshStats()
    }

    func refreshStats() {
        let records = log.readAll()
        let cal = Calendar(identifier: .iso8601) // weeks start on Monday
        var totals: [Category: Double] = [:]
        if let week = cal.dateInterval(of: .weekOfYear, for: Date()) {
            for r in records where week.contains(r.start) { totals[r.category, default: 0] += r.minutes }
        }
        weekMinutes = totals
        todayCount = records.filter { $0.status == .completed && cal.isDateInToday($0.start) }.count
        objectWillChange.send()
    }

    var weekTotal: Double { weekMinutes.values.reduce(0, +) }

    func share(_ c: Category) -> Double { weekTotal > 0 ? (weekMinutes[c] ?? 0) / weekTotal : 0 }

    // MARK: Technical-time target

    /// Optional schedule, set with:
    /// defaults write com.tomoeisozaki.focus targetSchedule -array "2026-11-02=70" "2026-11-30=50"
    /// The latest entry on or before today wins. Without a matching entry the manual setting is used.
    var hasSchedule: Bool { !(defaults.stringArray(forKey: "targetSchedule") ?? []).isEmpty }

    private func scheduledTarget(for date: Date) -> Int? {
        guard let items = defaults.stringArray(forKey: "targetSchedule"), !items.isEmpty else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        var best: (date: Date, pct: Int)?
        for item in items {
            let parts = item.split(separator: "=")
            guard parts.count == 2, let d = f.date(from: String(parts[0])), let p = Int(parts[1]) else { continue }
            if d <= date, best == nil || d > best!.date { best = (d, p) }
        }
        return best?.pct
    }

    var technicalTarget: Int? {
        if let s = scheduledTarget(for: Date()) { return s }
        return targetEnabled ? targetPercent : nil
    }
}

// MARK: - Views

struct LoginToggle: View {
    let label: String
    @State private var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle(label, isOn: Binding(get: { on }, set: { v in
            do {
                if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {}
            on = SMAppService.mainApp.status == .enabled
        }))
        .toggleStyle(.checkbox)
    }
}

struct ContentView: View {
    @EnvironmentObject var timer: FocusTimer
    @State private var manualMinutes = 30
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(timer.phase.title(timer.lang) + (timer.isPaused ? timer.tr(" · dijeda", " · paused") : ""))
                    .font(.headline)
                Spacer()
                Text("\(timer.tr("Tuntas hari ini", "Done today")): \(timer.todayCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(timer.timeString)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            ProgressView(value: timer.progress)
                .tint(timer.phase.isBreak ? .green : timer.category.color)

            Picker(timer.tr("Kategori", "Category"), selection: $timer.category) {
                ForEach(Category.allCases) { c in Text(c.name(timer.lang)).tag(c) }
            }
            .disabled(timer.phase == .focus)

            TextField(timer.tr("Sedang mengerjakan apa? (opsional)", "What are you working on? (optional)"), text: $timer.note)
                .textFieldStyle(.roundedBorder)

            controls

            Divider()
            weekSummary
            Divider()

            DisclosureGroup(timer.tr("Pengaturan & catat manual", "Settings & manual log"), isExpanded: $showSettings) {
                settings.padding(.top, 6)
            }
            .font(.callout)

            HStack {
                Button(timer.tr("Buka log CSV", "Open CSV log")) {
                    NSWorkspace.shared.activateFileViewerSelecting([timer.log.url])
                }
                Spacer()
                Button(timer.tr("Keluar", "Quit")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { timer.refreshStats() }
    }

    @ViewBuilder var controls: some View {
        HStack(spacing: 8) {
            switch timer.phase {
            case .idle:
                Button { timer.startFocus() } label: {
                    Label(timer.tr("Mulai fokus \(timer.focusMinutes) menit", "Start \(timer.focusMinutes)-minute focus"),
                          systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            case .focus:
                if timer.isPaused {
                    Button { timer.resume() } label: {
                        Label(timer.tr("Lanjut", "Resume"), systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button { timer.pause() } label: {
                        Label(timer.tr("Jeda", "Pause"), systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                Button { timer.finishFocusEarly() } label: {
                    Label(timer.tr("Selesai", "Finish"), systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            case .shortBreak, .longBreak:
                Button { timer.skipBreak() } label: {
                    Label(timer.tr("Lewati istirahat", "Skip break"), systemImage: "forward.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
    }

    var weekSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timer.tr("Minggu ini", "This week")).font(.subheadline.bold())
                Spacer()
                Text("\(timer.tr("Total", "Total")) \(timer.formatMinutes(timer.weekTotal))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Category.allCases) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Circle().fill(c.color).frame(width: 8, height: 8)
                        Text(c.name(timer.lang)).font(.caption)
                        Spacer()
                        Text("\(timer.formatMinutes(timer.weekMinutes[c] ?? 0)) · \(Int((timer.share(c) * 100).rounded()))%")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(c.color).frame(width: max(0, g.size.width * timer.share(c)))
                        }
                    }
                    .frame(height: 5)
                }
            }
            if let target = timer.technicalTarget {
                let pct = Int((timer.share(.technical) * 100).rounded())
                let empty = timer.weekTotal == 0
                let ok = pct <= target
                Label(empty
                      ? timer.tr("Target porsi teknis: maks \(target)%", "Technical-time target: max \(target)%")
                      : timer.tr("Porsi teknis \(pct)% · target maks \(target)%", "Technical time \(pct)% · target max \(target)%"),
                      systemImage: empty ? "target" : (ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                    .font(.caption)
                    .foregroundStyle(empty ? Color.secondary : (ok ? Color.green : Color.orange))
            }
        }
    }

    var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(timer.tr("Bahasa", "Language"), selection: $timer.language) {
                ForEach(AppLanguage.allCases) { l in Text(l.pickerLabel).tag(l) }
            }
            Divider()
            Stepper("\(timer.tr("Fokus", "Focus")): \(timer.focusMinutes) \(timer.tr("menit", "min"))",
                    value: $timer.focusMinutes, in: 5...120, step: 5)
            Stepper("\(timer.tr("Istirahat", "Break")): \(timer.shortBreakMinutes) \(timer.tr("menit", "min"))",
                    value: $timer.shortBreakMinutes, in: 1...30)
            Stepper("\(timer.tr("Istirahat panjang", "Long break")): \(timer.longBreakMinutes) \(timer.tr("menit", "min"))",
                    value: $timer.longBreakMinutes, in: 5...60, step: 5)
            Stepper(timer.tr("Istirahat panjang tiap \(timer.sessionsBeforeLong) sesi",
                             "Long break every \(timer.sessionsBeforeLong) sessions"),
                    value: $timer.sessionsBeforeLong, in: 1...8)
            Divider()
            Toggle(timer.tr("Tampilkan target porsi teknis", "Show technical-time target"), isOn: $timer.targetEnabled)
                .toggleStyle(.checkbox)
            Stepper("\(timer.tr("Maks", "Max")) \(timer.targetPercent)%", value: $timer.targetPercent, in: 5...100, step: 5)
                .disabled(!timer.targetEnabled)
            if timer.hasSchedule {
                Text(timer.tr("Jadwal target aktif dan mengikuti tanggal.", "A target schedule is active and follows the date."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text(timer.tr("Catat waktu tanpa timer (misalnya rapat), memakai kategori yang dipilih di atas.",
                          "Log time without the timer (a meeting, say), using the category selected above."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Stepper("\(manualMinutes) \(timer.tr("menit", "min"))", value: $manualMinutes, in: 5...480, step: 5)
                Spacer()
                Button(timer.tr("Catat", "Log")) { timer.logManual(minutes: manualMinutes) }
            }
            LoginToggle(label: timer.tr("Buka otomatis saat Mac menyala", "Open at login"))
        }
    }
}

// MARK: - App

@main
struct FocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timer = FocusTimer()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(timer)
        } label: {
            if timer.phase == .idle {
                Image(systemName: "timer")
            } else {
                Text(timer.menuTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
