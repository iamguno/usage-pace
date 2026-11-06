import Foundation

// MARK: - 터미널 없이 사용량 받아오기
//
// 설치된 Claude Code를 화면 없는 모드(stream-json)로 잠깐 켜고, 메시지 대신
// 「사용량 알려 줘」 제어 요청(get_usage)만 보냄. 데스크톱 앱이 사용량을 보여 줄 때와 같은 방식이라
// 모델을 부르지 않고 토큰도 쓰지 않음. Claude Code는 받은 사용량을 1분 동안만 다시 쓰므로 값은 길어야 1분 전 것.
// 받은 5시간·주간 사용률과 리셋 시각을 상태 표시줄 도우미와 같은 형식으로 rate_limits.json에 저장.
//
// - 로그인 정보는 Claude Code가 평소처럼 직접 처리하고, 이 앱은 읽거나 저장하지 않음
// - 앱 자체는 네트워크에 접속하지 않음 (접속은 Claude Code가 함)

enum ClaudeProbe {
    /// 자동 갱신 간격 (토큰을 쓰지 않으니 자주 받아도 됨)
    static let interval: TimeInterval = 5 * 60
    static let timeout: TimeInterval = 45

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
        // 자동 업데이트·오류 보고 같은 부가 통신은 끔 (사용량 요청에는 영향 없음)
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

        let args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json", "--verbose",
            "--strict-mcp-config",
            "--no-session-persistence",
            // 사용자의 훅(알림·소리 등)이 갱신할 때마다 실행되지 않게
            "--settings", #"{"disableAllHooks":true}"#,
        ]
        let requests: [[String: Any]] = [
            ["subtype": "initialize"],
            ["subtype": "get_usage", "skip_behaviors": true],
        ]
        guard let reply = control(cli, args, requests: requests, wanted: "get_usage", cwd: workDir, env: env, timeout: timeout) else {
            return .failure(.failed("could not start claude"))
        }
        if reply.timedOut { return .failure(.failed("timed out")) }
        guard let r = reply.response else { return .failure(.failed(reply.errorTail.isEmpty ? "no answer" : String(reply.errorTail.prefix(160)))) }
        guard r["subtype"] as? String == "success", let body = r["response"] as? [String: Any] else {
            return .failure(.failed(String(((r["error"] as? String) ?? "get_usage failed").prefix(160))))
        }
        guard body["rate_limits_available"] as? Bool == true, let limits = body["rate_limits"] as? [String: Any] else {
            return .failure(.noUsage)
        }

        // utilization은 이미 0~100 퍼센트, resets_at은 ISO 시각 → 상태 표시줄과 같은 초 단위로
        var saved: [String: Any] = ["updated_at": Date().timeIntervalSince1970]
        for key in ["five_hour", "seven_day"] {
            guard let w = limits[key] as? [String: Any],
                  let u = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            var entry: [String: Any] = ["used_percentage": u]
            if let reset = seconds(w["resets_at"]) { entry["resets_at"] = reset }
            saved[key] = entry
        }
        guard saved.count > 1 else { return .failure(.noUsage) }

        do {
            try fm.createDirectory(at: Paths.dataDir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: saved)
            try data.write(to: Paths.usageFile, options: .atomic)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        return .success(saved)
    }

    /// "2026-11-06T19:40:00.799482+00:00" 같은 시각(또는 초·밀리초 숫자) → 1970년부터의 초
    static func seconds(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue > 1e12 ? n.doubleValue / 1000 : n.doubleValue }
        guard let text = value as? String else { return nil }
        // ISO8601DateFormatter는 소수 초를 세 자리까지만 읽어서, 소수 부분은 떼고 읽음
        let plain = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: plain)?.timeIntervalSince1970
    }

    // MARK: 제어 요청 보내기

    struct Reply {
        let response: [String: Any]?
        let timedOut: Bool
        let errorTail: String
    }

    /// stream-json 모드의 claude에 제어 요청을 한 줄씩 보내고, 원하는 요청(wanted)의 답이 오면 입력을 닫아 끝냄
    static func control(_ exe: URL, _ args: [String], requests: [[String: Any]], wanted: String,
                        cwd: URL, env: [String: String], timeout: TimeInterval) -> Reply? {
        signal(SIGPIPE, SIG_IGN)     // claude가 먼저 끝나도 앱이 같이 꺼지지 않게
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.currentDirectoryURL = cwd
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        let lock = NSLock()
        let done = DispatchSemaphore(value: 0)
        var buffer = Data(), errData = Data()
        var found: [String: Any]?
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            lock.lock(); defer { lock.unlock() }
            if chunk.isEmpty { h.readabilityHandler = nil; done.signal(); return }   // 답 없이 끝남
            guard found == nil else { return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      obj["type"] as? String == "control_response",
                      let r = obj["response"] as? [String: Any],
                      r["request_id"] as? String == wanted else { continue }
                found = r
                done.signal()
                return
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            lock.lock(); errData.append(chunk); if errData.count > 8192 { errData = errData.suffix(4096) }; lock.unlock()
        }
        do { try p.run() } catch { return nil }

        var input = Data()
        for req in requests {
            let msg: [String: Any] = ["type": "control_request", "request_id": req["subtype"] as? String ?? "", "request": req]
            if let d = try? JSONSerialization.data(withJSONObject: msg) { input.append(d); input.append(0x0A) }
        }
        try? inPipe.fileHandleForWriting.write(contentsOf: input)
        let waited = done.wait(timeout: .now() + timeout)

        // 입력을 닫으면 claude가 스스로 끝남. 5초 안에 안 끝나면 끔
        try? inPipe.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(5)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate() }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        lock.lock(); defer { lock.unlock() }
        var tail = String(decoding: errData, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? ""
        if tail.isEmpty, !p.isRunning, p.terminationStatus != 0 { tail = "exit \(p.terminationStatus)" }
        return Reply(response: found, timedOut: waited == .timedOut && found == nil, errorTail: tail)
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
