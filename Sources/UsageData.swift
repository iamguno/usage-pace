import Foundation
import Security

// MARK: - Model

/// 하나의 한도 창(5시간 세션 또는 7일 주간).
struct LimitWindow {
    /// 사용률 (0~100)
    let utilization: Double
    /// 리셋 시각 (창이 아직 시작되지 않았거나 이미 리셋됐으면 nil)
    let resetsAt: Date?
    /// 창 길이 (초)
    let length: TimeInterval

    var startsAt: Date? { resetsAt?.addingTimeInterval(-length) }

    /// 창 안에서 시간이 얼마나 지났는지 (0~1)
    func elapsedFraction(now: Date = Date()) -> Double? {
        guard let start = startsAt else { return nil }
        return min(max(now.timeIntervalSince(start) / length, 0), 1)
    }

    func elapsedTime(now: Date = Date()) -> TimeInterval? {
        guard let start = startsAt else { return nil }
        return min(max(now.timeIntervalSince(start), 0), length)
    }

    func remaining(now: Date = Date()) -> TimeInterval? {
        guard let r = resetsAt else { return nil }
        return max(r.timeIntervalSince(now), 0)
    }
}

struct UsageSnapshot {
    var session: LimitWindow?
    var weekly: LimitWindow?
    /// Claude Code가 마지막으로 값을 넘겨준 시각
    var fetchedAt: Date
}

enum UsageError: LocalizedError {
    case parse
    case settingsUnreadable
    case settingsWrite(String)

    var errorDescription: String? {
        switch self {
        case .parse: return L("error.parse")
        case .settingsUnreadable: return L("error.settingsUnreadable")
        case .settingsWrite(let why): return L("error.settingsWrite", why)
        }
    }
}

// MARK: - Paths

enum Paths {
    private static let env = ProcessInfo.processInfo.environment

    /// 앱 데이터 폴더 (도우미 프로그램, 사용량 파일)
    static var dataDir: URL {
        env["USAGEPACE_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/UsagePace")
    }
    static var usageFile: URL { dataDir.appendingPathComponent("rate_limits.json") }
    static var previousStatusLine: URL { dataDir.appendingPathComponent("previous-statusline.json") }
    static var installedBridge: URL { dataDir.appendingPathComponent("statusline-bridge") }

    /// Claude Code 설정 폴더 (~/.claude)
    static var claudeDir: URL {
        if let d = env["USAGEPACE_CLAUDE_DIR"] ?? env["CLAUDE_CONFIG_DIR"] { return URL(fileURLWithPath: d) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }
    static var claudeSettings: URL { claudeDir.appendingPathComponent("settings.json") }

    /// 앱 번들 안의 도우미
    static var bundledBridge: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/usagepace-statusline")
    }
}

// MARK: - 사용량 읽기 (도우미가 저장한 파일)

enum StatusLineSource {
    static let fiveHours: TimeInterval = 5 * 3600
    static let sevenDays: TimeInterval = 7 * 24 * 3600

    /// 파일이 없으면 nil (아직 Claude Code가 값을 넘겨준 적 없음)
    static func read(now: Date = Date()) throws -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: Paths.usageFile) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updated = (obj["updated_at"] as? NSNumber)?.doubleValue else { throw UsageError.parse }

        func window(_ key: String, _ length: TimeInterval) -> LimitWindow? {
            guard let w = obj[key] as? [String: Any] else { return nil }
            let used = (w["used_percentage"] as? NSNumber)?.doubleValue ?? 0
            let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            // 이미 리셋 시각이 지났으면 새 창이 아직 시작 안 된 것으로 표시
            if let r = reset, r <= now { return LimitWindow(utilization: 0, resetsAt: nil, length: length) }
            return LimitWindow(utilization: used, resetsAt: reset, length: length)
        }

        return UsageSnapshot(
            session: window("five_hour", fiveHours),
            weekly: window("seven_day", sevenDays),
            fetchedAt: Date(timeIntervalSince1970: updated)
        )
    }
}

// MARK: - Claude Code 연결 (settings.json의 statusLine 설정)

enum ClaudeCodeConnector {
    /// settings.json에 들어가는 명령 (경로에 공백이 있어 따옴표로 감쌈)
    static var bridgeCommand: String { "\"\(Paths.installedBridge.path)\"" }

    static var isConnected: Bool {
        guard let s = try? readSettings(),
              let line = s["statusLine"] as? [String: Any] else { return false }
        return line["command"] as? String == bridgeCommand
    }

    /// 연결: 도우미 설치 → 기존 statusLine 명령 보관 → statusLine을 도우미로 교체
    static func connect() throws {
        var settings = try readSettings()
        try installBridge()

        var line = settings["statusLine"] as? [String: Any] ?? [:]
        if let existing = line["command"] as? String, existing != bridgeCommand {
            try writeJSON(["command": existing], to: Paths.previousStatusLine)
        }
        line["type"] = "command"
        line["command"] = bridgeCommand
        settings["statusLine"] = line
        try writeSettings(settings)
    }

    /// 연결 해제: 원래 statusLine 명령 복원 (없었으면 statusLine 항목 제거)
    static func disconnect() throws {
        var settings = try readSettings()
        if var line = settings["statusLine"] as? [String: Any], line["command"] as? String == bridgeCommand {
            if let d = try? Data(contentsOf: Paths.previousStatusLine),
               let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let previous = p["command"] as? String {
                line["command"] = previous
                settings["statusLine"] = line
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeSettings(settings)
        }
        let fm = FileManager.default
        try? fm.removeItem(at: Paths.previousStatusLine)
        try? fm.removeItem(at: Paths.usageFile)
        try? fm.removeItem(at: Paths.installedBridge)
    }

    /// 앱 업데이트 후에도 최신 도우미를 쓰도록 실행 시마다 덮어씀
    static func refreshBridgeIfConnected() {
        if isConnected { try? installBridge() }
    }

    // MARK: Internals

    private static func installBridge() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Paths.dataDir, withIntermediateDirectories: true)
            let tmp = Paths.dataDir.appendingPathComponent(".statusline-bridge.tmp")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: Paths.bundledBridge, to: tmp)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            if fm.fileExists(atPath: Paths.installedBridge.path) {
                _ = try fm.replaceItemAt(Paths.installedBridge, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: Paths.installedBridge)
            }
        } catch {
            throw UsageError.settingsWrite(error.localizedDescription)
        }
    }

    /// 파일이 없으면 빈 설정, 읽을 수 없거나 JSON이 아니면 오류 (아무것도 바꾸지 않음)
    private static func readSettings() throws -> [String: Any] {
        let url = Paths.claudeSettings
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.settingsUnreadable
        }
        return obj
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        // 심볼릭 링크(dotfiles 관리 등)면 실제 파일에 씀
        let url = Paths.claudeSettings.resolvingSymlinksInPath()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 바꾸기 전 백업
            if fm.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("usagepace-backup")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: url, to: backup)
            }
            try writeJSON(settings, to: url)
        } catch let e as UsageError {
            throw e
        } catch {
            throw UsageError.settingsWrite(error.localizedDescription)
        }
    }

    private static func writeJSON(_ obj: [String: Any], to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try JSONSerialization.data(withJSONObject: obj,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            data.append(0x0A)
            try data.write(to: url, options: .atomic)
        } catch {
            throw UsageError.settingsWrite(error.localizedDescription)
        }
    }
}

// MARK: - 이전 버전 정리

enum LegacyCleanup {
    /// 개발 중 쓰던 이전 번들 ID들의 설정을 한 번만 가져옴
    static func migratePreferences() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedLegacyPrefs") else { return }
        for suite in ["app.usagepace.mac", "local.claudeusagepace"] {
            guard let old = UserDefaults(suiteName: suite) else { continue }
            for key in ["language", "menuWindow", "menuStyle"] where d.object(forKey: key) == nil {
                if let v = old.object(forKey: key) { d.set(v, forKey: key) }
            }
        }
        d.set(true, forKey: "migratedLegacyPrefs")
    }

    /// 이전 버전이 키체인에 저장했던 claude.ai 세션을 삭제 (더 이상 쓰지 않음)
    static func run() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "ClaudeUsagePace",
                                kSecAttrAccount as String: "claude.ai-sessionKey"]
        SecItemDelete(q as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "source")
    }
}
