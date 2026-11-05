import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Settings enums

enum MenuWindow: String, CaseIterable, Identifiable {
    case weekly, session
    var id: String { rawValue }
    var title: String { self == .weekly ? L("window.weekly") : L("window.session") }
}

enum MenuStyle: String, CaseIterable, Identifiable {
    case usedAndElapsed, usedAndDiff, usedOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .usedAndElapsed: return "47% / 29%"
        case .usedAndDiff: return "47% (+18)"
        case .usedOnly: return "47%"
        }
    }
}

// MARK: - Store

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    /// 사용량 파일 읽기 / Claude Code 연결 중 생긴 오류
    @Published var lastError: UsageError?
    @Published var now = Date()
    @Published var connected = false
    @Published var showSettings = false
    @Published var launchAtLogin = LoginItem.isEnabled {
        didSet { if launchAtLogin != LoginItem.isEnabled { LoginItem.set(launchAtLogin) } }
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language"); L10n.apply(language) }
    }
    @Published var menuWindow: MenuWindow {
        didSet { defaults.set(menuWindow.rawValue, forKey: "menuWindow") }
    }
    @Published var menuStyle: MenuStyle {
        didSet { defaults.set(menuStyle.rawValue, forKey: "menuStyle") }
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if !demo { LegacyCleanup.migratePreferences() }
        var lang = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system
        // 데모 모드(스크린샷용)는 DEMO_LANG으로 언어 지정, 저장된 설정은 건드리지 않음
        if demo, let code = ProcessInfo.processInfo.environment["DEMO_LANG"], let l = AppLanguage(rawValue: code) { lang = l }
        L10n.apply(lang)
        language = lang
        menuWindow = MenuWindow(rawValue: defaults.string(forKey: "menuWindow") ?? "") ?? .weekly
        menuStyle = MenuStyle(rawValue: defaults.string(forKey: "menuStyle") ?? "") ?? .usedAndElapsed

        if demo {
            snapshot = Self.demoSnapshot()
            connected = true
            return
        }
        LegacyCleanup.run()
        ClaudeCodeConnector.refreshBridgeIfConnected()
        reload()
        // 파일 읽기는 가벼우므로 10초마다 확인 (시간 경과 %도 함께 갱신)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// 도우미가 저장한 사용량 파일 다시 읽기
    func reload() {
        now = Date()
        if demo { return }
        connected = ClaudeCodeConnector.isConnected
        do {
            snapshot = try StatusLineSource.read(now: now)
            if case .parse? = lastError { lastError = nil }
        } catch let e as UsageError {
            lastError = e
        } catch {
            lastError = .parse
        }
    }

    func connect() {
        do {
            try ClaudeCodeConnector.connect()
            lastError = nil
        } catch let e as UsageError {
            lastError = e
        } catch {
            lastError = .settingsWrite(error.localizedDescription)
        }
        reload()
    }

    func disconnect() {
        do {
            try ClaudeCodeConnector.disconnect()
            lastError = nil
        } catch let e as UsageError {
            lastError = e
        } catch {
            lastError = .settingsWrite(error.localizedDescription)
        }
        reload()
    }

    var errorMessage: String? { lastError?.errorDescription }

    // MARK: Menu bar text

    var menuText: String {
        guard let s = snapshot,
              let w = (menuWindow == .weekly ? s.weekly : s.session) else { return "–" }
        let used = Int(w.utilization.rounded())
        let elapsed = w.elapsedFraction(now: now).map { Int(($0 * 100).rounded()) }
        switch menuStyle {
        case .usedOnly:
            return "\(used)%"
        case .usedAndElapsed:
            return elapsed.map { "\(used)% / \($0)%" } ?? "\(used)%"
        case .usedAndDiff:
            guard let e = elapsed else { return "\(used)%" }
            let d = used - e
            return "\(used)% (\(d >= 0 ? "+" : "")\(d))"
        }
    }

    // MARK: Demo data (스크린샷/미리보기용)

    static func demoSnapshot() -> UsageSnapshot {
        let now = Date()
        return UsageSnapshot(
            session: LimitWindow(utilization: 23, resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60), length: StatusLineSource.fiveHours),
            weekly: LimitWindow(utilization: 47, resetsAt: now.addingTimeInterval(4 * 86400 + 22 * 3600), length: StatusLineSource.sevenDays),
            fetchedAt: now.addingTimeInterval(-3 * 60)
        )
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Login item error: \(error)")
        }
    }
}

// MARK: - Entry point

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { renderSnapshot(to: args[i + 1]) }
            exit(0)
        }
        // 명령줄에서 연결/해제/상태 확인 (스크립트·테스트용)
        if args.contains("--connect") || args.contains("--disconnect") || args.contains("--status") {
            do {
                if args.contains("--connect") { try ClaudeCodeConnector.connect() }
                if args.contains("--disconnect") { try ClaudeCodeConnector.disconnect() }
                print(ClaudeCodeConnector.isConnected ? "connected" : "not connected")
                if let s = try StatusLineSource.read() {
                    let iso = ISO8601DateFormatter()
                    for (name, w) in [("five_hour", s.session), ("seven_day", s.weekly)] {
                        guard let w else { print("\(name): -"); continue }
                        let elapsed = w.elapsedFraction().map { String(format: "%.1f%%", $0 * 100) } ?? "-"
                        print("\(name): used \(w.utilization)% elapsed \(elapsed) resets \(w.resetsAt.map(iso.string(from:)) ?? "-")")
                    }
                    print("updated: \(iso.string(from: s.fetchedAt))")
                } else {
                    print("no usage data yet")
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        UsagePaceApp.main()
    }

    /// 데모 데이터로 팝오버 화면을 PNG로 저장 (개발 확인용)
    /// SNAPSHOT_LANG=ko, SNAPSHOT_SETTINGS=1, SNAPSHOT_EMPTY=connect|waiting
    @MainActor
    static func renderSnapshot(to path: String) {
        let env = ProcessInfo.processInfo.environment
        if let code = env["SNAPSHOT_LANG"], let lang = AppLanguage(rawValue: code) { L10n.apply(lang) }
        let store = UsageStore(demo: true)
        store.showSettings = env["SNAPSHOT_SETTINGS"] != nil
        if let mins = env["SNAPSHOT_AGE_MIN"].flatMap(Double.init), let snap = store.snapshot {
            store.snapshot = UsageSnapshot(session: snap.session, weekly: snap.weekly,
                                           fetchedAt: Date().addingTimeInterval(-mins * 60))
        }
        switch env["SNAPSHOT_EMPTY"] {
        case "connect"?: store.snapshot = nil; store.connected = false
        case "waiting"?: store.snapshot = nil; store.connected = true
        default: break
        }
        for scheme in [ColorScheme.light, .dark] {
            let view = PopoverView(store: store)
                .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.97))
                .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let out = path.replacingOccurrences(of: ".png", with: scheme == .dark ? "-dark.png" : "-light.png")
            try? png.write(to: URL(fileURLWithPath: out))
            print("wrote \(out)")
        }
    }
}

struct UsagePaceApp: App {
    /// --demo: 예시 숫자로 실행 (스크린샷·홍보용, 실제 설정·데이터를 읽거나 바꾸지 않음)
    @StateObject private var store = UsageStore(demo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: AppIcons.menuBar)
                Text(store.menuText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
