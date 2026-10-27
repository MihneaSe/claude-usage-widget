// Claude Usage Widget for macOS - read-only Claude Code usage widget
// ---------------------------------------------------------------------------
// What it does, and nothing more:
//   * Every 2 minutes runs:  claude -p /usage --output-format text --no-session-persistence
//     (the same numbers as /usage in Claude Code; the slash command does not call the model)
//   * Shows session %, weekly % and (if reported) Fable weekly %, with time left to reset,
//     in a small floating card and in the menu bar.
// What it never does:
//   * No network calls of its own, no telemetry, no admin rights.
//   * No chat, no AI-generated scripts, no file scanning, no running other programs.
//   * Stores only window position and two switches in macOS user defaults.
// Built from source on your Mac by Install.command (swiftc, Xcode Command Line Tools).
// ---------------------------------------------------------------------------

import AppKit

let appVersion = "1.2.2"   // keep in sync with VERSION, widget.ps1, setup.ps1 and CHANGELOG.md
let probeInterval: TimeInterval = 120
let probeTimeout: TimeInterval = 45

// MARK: - Colours (Claude light theme)

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Palette {
    static let card = NSColor(hex: 0xFAF9F5)
    static let border = NSColor(hex: 0xE3E0D5)
    static let label = NSColor(hex: 0x73726C)
    static let detail = NSColor(hex: 0x5E5D59)
    static let muted = NSColor(hex: 0xB0AEA5)
    static let amber = NSColor(hex: 0xB8862B)
    static let red = NSColor(hex: 0xB53A31)

    // colour of the % number, one step per 20%
    static func forPercent(_ p: Int) -> NSColor {
        switch p {
        case ..<20: return NSColor(hex: 0x3D3D3A)   // ink
        case ..<40: return NSColor(hex: 0x5E8C4E)   // sage
        case ..<60: return NSColor(hex: 0xB8862B)   // amber
        case ..<80: return NSColor(hex: 0xC96442)   // clay
        default:    return NSColor(hex: 0xB53A31)   // red
        }
    }
}

// MARK: - Parsing /usage

struct UsageLine {
    let pct: Int
    let reset: Date?
}

struct Usage {
    var session: UsageLine?
    var week: UsageLine?
    var fable: UsageLine?
}

enum UsageParser {
    static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }

    static func firstMatch(_ pattern: String, in s: String, options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    static func hour24(_ h: Int, _ ampm: String) -> Int {
        if ampm.lowercased() == "am" { return h == 12 ? 0 : h }
        return h == 12 ? 12 : h + 12
    }

    // "Oct 23, 7:29pm (Europe/Paris)", "Oct 23 at 7pm" or just "11:59pm"
    static func parseReset(_ s: String) -> Date? {
        var tz = TimeZone.current
        if let m = firstMatch("\\(([A-Za-z_]+(?:/[A-Za-z0-9_+-]+)+|UTC)\\)", in: s),
           let id = group(m, 1, in: s), let t = TimeZone(identifier: id) {
            tz = t
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = Date()
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

        if let m = firstMatch("([A-Za-z]{3})\\s+(\\d{1,2}),?\\s*(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*([ap]m)",
                              in: s, options: .caseInsensitive),
           let monStr = group(m, 1, in: s), let mon = months.firstIndex(of: monStr.lowercased()),
           let day = group(m, 2, in: s).flatMap({ Int($0) }),
           let h = group(m, 3, in: s).flatMap({ Int($0) }),
           let ap = group(m, 5, in: s) {
            var dc = DateComponents()
            dc.year = cal.component(.year, from: now)
            dc.month = mon + 1
            dc.day = day
            dc.hour = hour24(h, ap)
            dc.minute = group(m, 4, in: s).flatMap { Int($0) } ?? 0
            guard var d = cal.date(from: dc) else { return nil }
            if d < now.addingTimeInterval(-30 * 86400) {   // around New Year
                d = cal.date(byAdding: .year, value: 1, to: d) ?? d
            }
            return d
        }

        if let m = firstMatch("(\\d{1,2})(?::(\\d{2}))?\\s*([ap]m)", in: s, options: .caseInsensitive),
           let h = group(m, 1, in: s).flatMap({ Int($0) }),
           let ap = group(m, 3, in: s) {
            var dc = cal.dateComponents([.year, .month, .day], from: now)
            dc.hour = hour24(h, ap)
            dc.minute = group(m, 2, in: s).flatMap { Int($0) } ?? 0
            guard var d = cal.date(from: dc) else { return nil }
            if d < now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return d
        }
        return nil
    }

    static func line(_ text: String, label: String) -> UsageLine? {
        let pattern = NSRegularExpression.escapedPattern(for: label) + "\\s*(\\d{1,3})%([^\\r\\n]*)"
        guard let m = firstMatch(pattern, in: text),
              let pct = group(m, 1, in: text).flatMap({ Int($0) }) else { return nil }
        var reset: Date? = nil
        if let rest = group(m, 2, in: text), let r = rest.range(of: "resets") {
            reset = parseReset(String(rest[r.upperBound...]))
        }
        return UsageLine(pct: max(0, min(100, pct)), reset: reset)
    }

    static func parse(_ raw: String) -> Usage? {
        let text = raw.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        let u = Usage(session: line(text, label: "Current session:"),
                      week: line(text, label: "Current week (all models):"),
                      fable: line(text, label: "Current week (Fable):"))
        if u.session == nil && u.week == nil { return nil }
        return u
    }

    static func timeLeft(_ reset: Date?) -> String {
        guard let reset = reset else { return "not started" }
        let secs = reset.timeIntervalSinceNow
        if secs <= 0 { return "resetting..." }
        let mins = Int((secs / 60).rounded(.up))
        let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
        if d > 0 { return "resets in \(d)d \(h)h" }
        if h > 0 { return String(format: "resets in %ldh %02ldm", h, m) }
        return "resets in \(m)m"
    }
}

// MARK: - Running Claude Code

enum Claude {
    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    static func find() -> String? {
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        // last resort: ask the login shell (apps don't get your Terminal PATH)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (out.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: out)) ? out : nil
    }

    // Runs /usage off the main thread; calls back on the main thread with the text (nil on failure).
    static func usage(at path: String, completion: @escaping (String?) -> Void) {
        let homeDir = home
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["-p", "/usage", "--output-format", "text", "--no-session-persistence"]
            // Apps started from Finder get a bare environment and "/" as working folder;
            // give claude the same basics it has in Terminal.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(homeDir)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            env["HOME"] = env["HOME"] ?? homeDir
            if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
            env["NO_COLOR"] = "1"
            p.environment = env
            p.currentDirectoryURL = URL(fileURLWithPath: homeDir)
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out   // keep error messages too, so we can show what went wrong
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + probeTimeout, execute: killer)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            var text = String(data: data, encoding: .utf8)
            if p.terminationReason != .exit { text = (text ?? "") + "\n[timed out after \(Int(probeTimeout)) s]" }
            let result = text
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// MARK: - Diagnostics (only written when /usage can't be read; stays on this Mac)

enum Diagnostics {
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Claude Usage Widget/last-output.txt")
    }
    static func save(_ text: String, claudePath: String?) {
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let header = "Claude Usage Widget v\(appVersion) - \(Date())\nclaude: \(claudePath ?? "not found")\n" +
                     "command: claude -p /usage --output-format text --no-session-persistence\n---\n"
        try? (header + text).write(to: file, atomically: true, encoding: .utf8)
    }
}

// MARK: - Views

final class CardView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) {
        onDragStart?()
        window?.performDrag(with: event)
        onDragEnd?()
    }
}

final class UsageBlock {
    let stack = NSStackView()
    let title = NSTextField(labelWithString: "")
    let pct = NSTextField(labelWithString: "--%")
    let left = NSTextField(labelWithString: "")

    init(_ name: String) {
        title.stringValue = name
        title.font = .systemFont(ofSize: 11)
        title.textColor = Palette.label
        pct.font = .systemFont(ofSize: 30, weight: .semibold)
        pct.textColor = Palette.muted
        left.font = .systemFont(ofSize: 13, weight: .medium)
        left.textColor = Palette.detail
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        for v in [title, pct, left] { stack.addArrangedSubview(v) }
    }

    func show(_ line: UsageLine?) {
        guard let line = line else {
            pct.stringValue = "--%"
            pct.textColor = Palette.muted
            left.stringValue = ""
            return
        }
        pct.stringValue = "\(line.pct)%"
        pct.textColor = Palette.forPercent(line.pct)
        left.stringValue = UsageParser.timeLeft(line.reset)
    }
}

func separatorLine() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = Palette.border.cgColor
    v.translatesAutoresizingMaskIntoConstraints = false
    v.heightAnchor.constraint(equalToConstant: 1).isActive = true
    v.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
    return v
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let defaults = UserDefaults.standard
    var panel: NSPanel!
    var card: CardView!
    var statusItem: NSStatusItem!
    let session = UsageBlock("Session")
    let week = UsageBlock("Week")
    let fable = UsageBlock("Week - Fable")
    var fableSep: NSView!
    let status = NSTextField(labelWithString: "loading...")

    var claudePath: String?
    var usage: Usage?
    var lastOk: Date?
    var lastError = ""
    var probing = false
    var nextProbe = Date()
    var dragging = false

    var topmost: Bool {
        get { defaults.object(forKey: "topmost") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "topmost") }
    }
    var fadeOnHover: Bool {
        get { defaults.object(forKey: "fadeOnHover") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fadeOnHover") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()
        claudePath = Claude.find()
        if claudePath == nil {
            lastError = "Claude Code not found"
        }
        Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        tick()
    }

    // ---- window
    func buildPanel() {
        card = CardView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Palette.card.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Palette.border.cgColor

        status.font = .systemFont(ofSize: 11)
        status.textColor = Palette.muted
        fableSep = separatorLine()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let views: [NSView] = [session.stack, separatorLine(), week.stack, fableSep, fable.stack, status]
        for v in views { stack.addArrangedSubview(v) }
        fableSep.isHidden = true
        fable.stack.isHidden = true

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 130, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = topmost ? .floating : .normal
        panel.contentView = card

        card.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        card.onDragStart = { [weak self] in
            self?.dragging = true
            self?.fade(to: 1)
        }
        card.onDragEnd = { [weak self] in
            guard let self = self else { return }
            self.dragging = false
            self.defaults.set(Double(self.panel.frame.origin.x), forKey: "left")
            self.defaults.set(Double(self.panel.frame.origin.y), forKey: "bottom")
        }
        card.menu = makeMenu()

        resizePanel()
        placePanel()
        panel.orderFrontRegardless()
    }

    func resizePanel() {
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize
        if size == panel.frame.size { return }
        var f = panel.frame
        f.origin.y += f.size.height - size.height   // keep the top edge in place
        f.size = size
        panel.setFrame(f, display: true)
    }

    func placePanel() {
        var origin = NSPoint(x: 100, y: 500)
        if let x = defaults.object(forKey: "left") as? Double, let y = defaults.object(forKey: "bottom") as? Double {
            let p = NSPoint(x: x, y: y)
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(p) }) {
                origin = p
            }
        } else if let screen = NSScreen.main {
            origin = NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 24,
                             y: screen.visibleFrame.maxY - panel.frame.height - 24)
        }
        panel.setFrameOrigin(origin)
    }

    func hoverChanged(_ inside: Bool) {
        if inside && fadeOnHover && !dragging { fade(to: 0.10) } else { fade(to: 1) }
    }

    func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = alpha
        }
    }

    // ---- menu bar
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "--%"
        statusItem.button?.toolTip = "Claude Usage Widget v\(appVersion)"
        statusItem.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let m = NSMenu()
        let ver = NSMenuItem(title: "Claude Usage Widget v\(appVersion)", action: nil, keyEquivalent: "")
        ver.isEnabled = false
        m.addItem(ver)
        m.addItem(.separator())
        m.addItem(item("Refresh now", #selector(refreshNow)))
        m.addItem(item("Show last error output", #selector(showLastOutput)))
        m.addItem(item("Show / hide widget", #selector(toggleWidget)))
        let top = item("Always on top", #selector(toggleTopmost))
        top.tag = 1
        m.addItem(top)
        let fadeItem = item("Fade on mouse-over", #selector(toggleFade))
        fadeItem.tag = 2
        m.addItem(fadeItem)
        m.addItem(.separator())
        m.addItem(item("Quit", #selector(quit)))
        m.delegate = self
        return m
    }

    func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc func refreshNow() { nextProbe = Date() }
    @objc func showLastOutput() {
        if FileManager.default.fileExists(atPath: Diagnostics.file.path) {
            NSWorkspace.shared.open(Diagnostics.file)
        } else {
            let a = NSAlert()
            a.messageText = "No errors so far"
            a.informativeText = "The widget saves what Claude Code returned only when it can't read your usage."
            a.runModal()
        }
    }
    @objc func toggleWidget() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.alphaValue = 1; panel.orderFrontRegardless() }
    }
    @objc func toggleTopmost() {
        topmost.toggle()
        panel.level = topmost ? .floating : .normal
    }
    @objc func toggleFade() { fadeOnHover.toggle() }
    @objc func quit() { NSApp.terminate(nil) }

    // ---- loop
    @objc func tick() {
        if !probing && Date() >= nextProbe {
            if claudePath == nil { claudePath = Claude.find() }
            if let path = claudePath {
                probing = true
                Claude.usage(at: path) { [weak self] text in self?.probeDone(text) }
            } else {
                lastError = "Claude Code not found"
                nextProbe = Date().addingTimeInterval(probeInterval)
            }
        }
        render()
    }

    func probeDone(_ text: String?) {
        probing = false
        nextProbe = Date().addingTimeInterval(probeInterval)
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "claude gave no answer"
            Diagnostics.save(text ?? "(nothing)", claudePath: claudePath)
            return
        }
        if let u = UsageParser.parse(text) {
            usage = u
            lastOk = Date()
            lastError = ""
        } else if text.range(of: "log ?in|not authenticated|auth", options: [.regularExpression, .caseInsensitive]) != nil {
            lastError = "not signed in"
            Diagnostics.save(text, claudePath: claudePath)
        } else {
            lastError = "unexpected output"
            Diagnostics.save(text, claudePath: claudePath)
        }
        render()
    }

    func render() {
        session.show(usage?.session)
        week.show(usage?.week)
        let hasFable = usage?.fable != nil
        if fable.stack.isHidden == hasFable {
            fable.stack.isHidden = !hasFable
            fableSep.isHidden = !hasFable
        }
        if hasFable { fable.show(usage?.fable) }

        // status line under the numbers
        var text = ""
        var color = Palette.muted
        if lastOk == nil {
            text = lastError.isEmpty ? "loading..." : lastError + " (see menu)"
            if !lastError.isEmpty { color = Palette.red }
        } else if let ok = lastOk, Date().timeIntervalSince(ok) > 3 * probeInterval {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            text = "stale - " + f.string(from: ok)
            color = Palette.amber
        }
        status.stringValue = text
        status.textColor = color
        status.isHidden = text.isEmpty
        resizePanel()

        // menu bar: session %, coloured
        if let s = usage?.session {
            let title = NSAttributedString(string: "\(s.pct)%", attributes: [
                .foregroundColor: Palette.forPercent(s.pct),
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            ])
            statusItem.button?.attributedTitle = title
            var tip = "Claude: session \(s.pct)%"
            if let w = usage?.week { tip += ", week \(w.pct)%" }
            if let f = usage?.fable { tip += ", Fable \(f.pct)%" }
            statusItem.button?.toolTip = tip
        } else {
            statusItem.button?.title = lastError.isEmpty ? "--%" : "!"
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1)?.state = topmost ? .on : .off
        menu.item(withTag: 2)?.state = fadeOnHover ? .on : .off
    }
}

// MARK: - Start (single instance)

let bundleId = Bundle.main.bundleIdentifier ?? "com.github.mihnease.claude-usage-widget"
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
