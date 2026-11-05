import Foundation

// MARK: - 터미널 없이 사용량 받아오기
//
// 설치된 Claude Code를 `claude -p`(화면 없는 모드)로 아주 작게 실행하면,
// 응답 스트림에 공식 `rate_limit_event`(5시간·주간 사용률과 리셋 시각)가 함께 옴.
// 그 값만 읽어서 상태 표시줄 도우미와 같은 형식으로 rate_limits.json에 저장.
//
// - 로그인 정보는 Claude Code가 평소처럼 직접 처리하고, 이 앱은 읽거나 저장하지 않음
// - 요청은 Haiku + 최소 시스템 프롬프트 + 도구·MCP·훅 없음 → 약 1,000 토큰
// - 앱 자체는 네트워크에 접속하지 않음 (접속은 Claude Code가 함)

enum ClaudeProbe {
    /// 자동 갱신 간격
    static let interval: TimeInterval = 15 * 60
    static let timeout: TimeInterval = 90

    enum Failure: Error {
        case notFound
        case noUsage
        case failed(String)

        var message: String {
            switch self {
            case .notFound: return L("auto.error.notFound")
            case .noUsage: return L("auto.error.noUsage")
            case .failed(let why): return L("auto.error.failed", why)
            }
        }
    }

    /// 한 번 실행해서 사용량 파일을 갱신. 성공하면 저장한 내용(JSON 객체)을 돌려줌.
    static func refresh() -> Result<[String: Any], Failure> {
        guard let cli = locateCLI() else { return .failure(.notFound) }

        let fm = FileManager.default
        // 빈 폴더에서 실행해서 프로젝트의 CLAUDE.md·설정을 읽지 않게 함
        let workDir = Paths.dataDir.appendingPathComponent("probe")
        try? fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        var env = ProcessInfo.processInfo.environment
        // Finder에서 실행된 앱은 PATH가 짧음 → claude가 있는 폴더(npm 설치면 node도 같은 곳)와 흔한 경로 추가
        let extra = [cli.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        // 자동 업데이트·오류 보고 같은 부가 통신은 끔 (사용량 값은 API 응답에 함께 오므로 영향 없음)
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

        let args = [
            "-p", "OK",
            "--model", "haiku",
            "--output-format", "stream-json", "--verbose",
            "--system-prompt", "Reply with OK.",
            "--tools", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--no-session-persistence",
            // 사용자의 훅(알림·소리 등)이 15분마다 실행되지 않게
            "--settings", #"{"disableAllHooks":true}"#,
        ]
        guard let out = run(cli, args, cwd: workDir, env: env, timeout: timeout) else {
            return .failure(.failed("could not start claude"))
        }
        if out.timedOut { return .failure(.failed("timed out")) }

        var windows: [String: Any]?
        var errorText: String?
        for line in String(decoding: out.stdout, as: UTF8.self).split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "rate_limit_event":
                let info = obj["rate_limit_info"] as? [String: Any]
                if let w = info?["unifiedWindows"] as? [String: Any] { windows = w }
            case "result":
                if obj["is_error"] as? Bool == true {
                    errorText = (obj["result"] as? String) ?? (obj["subtype"] as? String)
                }
            default:
                break
            }
        }

        // utilization은 0~1 비율 → 상태 표시줄과 같은 0~100 퍼센트로 변환
        var saved: [String: Any] = ["updated_at": Date().timeIntervalSince1970]
        for key in ["five_hour", "seven_day"] {
            guard let w = windows?[key] as? [String: Any],
                  let u = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            var entry: [String: Any] = ["used_percentage": (u * 10000).rounded() / 100]   // 소수 둘째 자리까지
            if let r = (w["resetsAt"] as? NSNumber)?.doubleValue { entry["resets_at"] = r }
            saved[key] = entry
        }
        guard saved.count > 1 else {
            if let e = errorText, !e.isEmpty { return .failure(.failed(String(e.prefix(160)))) }
            if out.status != 0 {
                let err = String(decoding: out.stderr, as: UTF8.self)
                    .split(separator: "\n").last.map(String.init) ?? "exit \(out.status)"
                return .failure(.failed(String(err.prefix(160))))
            }
            return .failure(.noUsage)
        }

        do {
            try fm.createDirectory(at: Paths.dataDir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: saved)
            try data.write(to: Paths.usageFile, options: .atomic)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        return .success(saved)
    }

    // MARK: claude 실행 파일 찾기

    static func locateCLI() -> URL? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        if let p = env["USAGEPACE_CLAUDE_BIN"], fm.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }

        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",          // 기본 설치 스크립트
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",           // Homebrew (Apple Silicon)
            "/usr/local/bin/claude",              // Homebrew (Intel), npm
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }

        // 그 밖의 위치(nvm 등)는 사용자 셸의 PATH로 찾기
        let shell = env["SHELL"].flatMap { fm.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        if let out = run(URL(fileURLWithPath: shell), ["-ilc", "command -v claude"], cwd: nil, env: nil, timeout: 10),
           !out.timedOut {
            for line in String(decoding: out.stdout, as: UTF8.self).split(separator: "\n").reversed() {
                let s = line.trimmingCharacters(in: .whitespaces)
                if s.hasPrefix("/"), fm.isExecutableFile(atPath: s) { return URL(fileURLWithPath: s) }
            }
        }
        return nil
    }

    // MARK: 프로세스 실행

    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: Data
        let timedOut: Bool
    }

    static func run(_ exe: URL, _ args: [String], cwd: URL?, env: [String: String]?, timeout: TimeInterval) -> Output? {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env { p.environment = env }
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in finished.signal() }
        do { try p.run() } catch { return nil }

        // 출력이 커도 막히지 않게 따로 읽음
        let reads = DispatchGroup()
        var outData = Data(), errData = Data()
        reads.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); reads.leave() }
        reads.enter()
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); reads.leave() }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            _ = finished.wait(timeout: .now() + 5)
        }
        _ = reads.wait(timeout: .now() + 5)
        return Output(status: p.isRunning ? -1 : p.terminationStatus, stdout: outData, stderr: errData, timedOut: timedOut)
    }
}
