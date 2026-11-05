// usagepace-statusline
//
// Claude Code의 statusLine 명령으로 실행되는 작은 도우미.
// 1. Claude Code가 stdin으로 넘겨주는 JSON에서 공식 `rate_limits` 값만 골라 파일로 저장
// 2. 사용자가 원래 쓰던 status line 명령이 있으면 그대로 실행해서 출력을 이어줌
//
// 로그인 정보·토큰은 전혀 읽거나 저장하지 않습니다.
// 문서: https://code.claude.com/docs/en/statusline (rate_limits.five_hour / seven_day)

import Foundation

let env = ProcessInfo.processInfo.environment
let dataDir: URL = env["USAGEPACE_DIR"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/UsagePace")

let input = FileHandle.standardInput.readDataToEndOfFile()

let parsed = try? JSONSerialization.jsonObject(with: input) as? [String: Any]

// 0. 진단용 실행 기록 (값은 남기지 않고 최상위 항목 이름만)
let runInfo: [String: Any] = [
    "ran_at": Date().timeIntervalSince1970,
    "input_bytes": input.count,
    "input_keys": (parsed?.keys.sorted() ?? []),
    "has_rate_limits": parsed?["rate_limits"] != nil,
]
if let d = try? JSONSerialization.data(withJSONObject: runInfo) {
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    try? d.write(to: dataDir.appendingPathComponent("last_run.json"), options: .atomic)
}

// 1. rate_limits 저장 (있을 때만 — 없으면 이전 값 유지)
if let obj = parsed,
   let limits = obj["rate_limits"] as? [String: Any] {
    var out: [String: Any] = ["updated_at": Date().timeIntervalSince1970]
    for key in ["five_hour", "seven_day"] {
        if let w = limits[key] as? [String: Any] { out[key] = w }
    }
    if out.count > 1, let data = try? JSONSerialization.data(withJSONObject: out) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try? data.write(to: dataDir.appendingPathComponent("rate_limits.json"), options: .atomic)
    }
}

// 2. 원래 status line 명령 이어서 실행
let previousFile = dataDir.appendingPathComponent("previous-statusline.json")
if let d = try? Data(contentsOf: previousFile),
   let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
   let command = p["command"] as? String, !command.isEmpty {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/sh")
    proc.arguments = ["-c", command]
    let stdinPipe = Pipe()
    proc.standardInput = stdinPipe
    proc.standardOutput = FileHandle.standardOutput
    proc.standardError = FileHandle.standardError
    do {
        try proc.run()
        stdinPipe.fileHandleForWriting.write(input)
        try? stdinPipe.fileHandleForWriting.close()
        proc.waitUntilExit()
        exit(proc.terminationStatus)
    } catch {
        exit(0)
    }
}
// 원래 명령이 없으면 아무것도 출력하지 않음
exit(0)
