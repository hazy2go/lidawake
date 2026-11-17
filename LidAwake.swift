// LidAwake: menu bar toggle for `pmset -a disablesleep`, so the Mac keeps
// running with the lid closed. Optional timer turns it back off.
//
// pmset needs root. On first use the app installs a narrow sudoers rule
// (/etc/sudoers.d/lidawake) via the standard admin password prompt; it allows
// only `pmset -a disablesleep 0|1` without a password, nothing else.

import SwiftUI
import ServiceManagement

private let pmset = "/usr/bin/pmset"
private let sudoersPath = "/etc/sudoers.d/lidawake"
private let endDateKey = "lidawake.endDate"

@MainActor
final class Awake: ObservableObject {
    @Published var isOn = false
    @Published var endDate: Date?
    @Published var now = Date()
    @Published var error: String?

    private var ticker: Timer?

    init() {
        endDate = UserDefaults.standard.object(forKey: endDateKey) as? Date
        refresh()
        // If a timer ran out while the app wasn't running, honor it now.
        if let end = endDate, end <= Date() { set(false) }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private var tickCount = 0
    private func tick() {
        now = Date()
        if let end = endDate, end <= now, isOn { set(false) }
        // Pick up changes made outside the app (e.g. pmset in Terminal).
        tickCount += 1
        if tickCount % 10 == 0 {
            refresh()
            checkBattery()
            checkHeat()
        }
    }

    /// Safety net: if it's on, unplugged, and at or below this %, turn off.
    static let lowBatteryCutoff = 10

    private func checkBattery() {
        guard isOn else { return }
        // e.g. " -InternalBattery-0 (id=...)	8%; discharging; 0:20 remaining"
        let out = run(pmset, ["-g", "batt"]).output
        guard out.contains("discharging"),
              let r = out.range(of: #"(\d+)%"#, options: .regularExpression),
              let pct = Int(out[r].dropLast()),
              pct <= Self.lowBatteryCutoff else { return }
        set(false)
        // Keep set()'s error if pmset failed, so we don't claim it turned off.
        if !isOn { error = "Turned off at \(pct)% battery so your Mac can sleep." }
    }

    /// Safety net: if it's on and macOS reports serious thermal pressure (fans
    /// maxed, performance throttled), turn off so a closed Mac can sleep and cool.
    private func checkHeat() {
        guard isOn, [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) else { return }
        set(false)
        if !isOn { error = "Turned off because your Mac was overheating." }
    }

    func refresh() {
        let out = run(pmset, ["-g"]).output
        let line = out.split(separator: "\n").first { $0.contains("SleepDisabled") }
        let on = line.map { $0.trimmingCharacters(in: .whitespaces).hasSuffix("1") } ?? false
        if on != isOn { isOn = on }
        if !on, endDate != nil { setEnd(nil) }
    }

    func set(_ on: Bool, for minutes: Int? = nil) {
        error = nil
        let arg = on ? "1" : "0"
        var r = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", arg])
        if r.status != 0 {
            guard installSudoers() else {
                error = "Needs admin permission (one time)."
                refresh(); return
            }
            r = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", arg])
        }
        if r.status != 0 { error = "pmset failed: \(r.output)" }
        setEnd(on ? minutes.map { Date().addingTimeInterval(Double($0) * 60) } : nil)
        refresh()
    }

    private func setEnd(_ d: Date?) {
        endDate = d
        if let d { UserDefaults.standard.set(d, forKey: endDateKey) }
        else { UserDefaults.standard.removeObject(forKey: endDateKey) }
    }

    var remaining: String? {
        guard isOn, let end = endDate else { return nil }
        let s = max(0, Int(end.timeIntervalSince(now)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Short label for the menu bar, e.g. "1h 20m" or "12m".
    var shortRemaining: String? {
        guard isOn, let end = endDate else { return nil }
        let mins = max(0, Int(ceil(end.timeIntervalSince(now) / 60)))
        return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
    }

    /// Writes the sudoers rule via the macOS admin password dialog.
    /// The staging file lives in /etc/sudoers.d with a "." in its name, which
    /// sudo ignores, is created by mktemp (root-owned, unpredictable), checked
    /// with visudo, then atomically renamed into place.
    private func installSudoers() -> Bool {
        let user = NSUserName()
        // macOS short names are [a-z0-9_.-]; refuse anything else rather than
        // put it into a sudoers rule.
        guard user.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else {
            return false
        }
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
        let shell = """
        T=$(/usr/bin/mktemp /etc/sudoers.d/lidawake.XXXXXX) || exit 1; \
        printf '%s\\n' '\(rule)' > "$T" && \
        /bin/chmod 0440 "$T" && /usr/sbin/chown root:wheel "$T" && \
        /usr/sbin/visudo -cf "$T" >/dev/null && \
        /bin/mv -f "$T" \(sudoersPath) || { /bin/rm -f "$T"; exit 1; }
        """
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges with prompt \"LidAwake needs permission once to control sleep with the lid closed.\""
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        return err == nil
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

@main
struct LidAwakeApp: App {
    @StateObject private var awake = Awake()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let durations: [(String, Int)] = [
        ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60),
        ("2 hours", 120), ("4 hours", 240), ("8 hours", 480),
    ]

    var body: some Scene {
        MenuBarExtra {
            if awake.isOn {
                Text(awake.remaining.map { "Awake with lid closed · off in \($0)" }
                     ?? "Awake with lid closed · no timer")
            } else {
                Text("Off · Mac sleeps when lid closes")
            }
            if let e = awake.error { Text(e) }
            Divider()

            Button(awake.isOn ? "Turn Off" : "Turn On (no timer)") {
                awake.set(!awake.isOn)
            }
            .keyboardShortcut("t")

            Menu(awake.isOn ? "Turn Off After…" : "Turn On For…") {
                ForEach(durations, id: \.1) { label, mins in
                    Button(label) { awake.set(true, for: mins) }
                }
                if awake.isOn && awake.endDate != nil {
                    Divider()
                    Button("Remove Timer") { awake.set(true) }
                }
            }

            Divider()
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            Button("Quit (turns off)") {
                if awake.isOn { awake.set(false) }
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            HStack(spacing: 3) {
                Image(systemName: awake.isOn ? "lock.open.laptopcomputer" : "lock.laptopcomputer")
                if let r = awake.shortRemaining { Text(r) }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
