import SwiftUI

// MARK: - Formatting (선택한 언어의 로케일을 따름)

enum Fmt {
    /// "4일 21시간", "4d 21h", "4日 21時間" …
    static func duration(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        var cal = Calendar.current
        cal.locale = L10n.locale
        f.calendar = cal
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        if t >= 86400 {
            f.allowedUnits = [.day, .hour]
        } else if t >= 3600 {
            f.allowedUnits = [.hour, .minute]
        } else {
            f.allowedUnits = [.minute]
            f.zeroFormattingBehavior = .default   // 1분 미만도 "0분"으로 표시
        }
        return f.string(from: max(t, 0)) ?? ""
    }

    /// 주간: 날짜+요일+시각, 세션: 시각만 (로케일 관례대로)
    static func resetDate(_ d: Date, weekly: Bool) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.setLocalizedDateFormatFromTemplate(weekly ? "MdEjmm" : "jmm")
        return f.string(from: d)
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: d)
    }

    /// "3분 전", "3 min. ago" …
    static func relative(_ d: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = L10n.locale
        f.unitsStyle = .short
        return f.localizedString(for: min(d, now), relativeTo: now)
    }

    static func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }
}

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.showSettings {
                SettingsView(store: store, done: { store.showSettings = false })
            } else {
                content
                footer
            }
        }
        .padding(16)
        .frame(width: 340)
        .id(store.language)   // 언어를 바꾸면 모든 하위 뷰를 다시 그림
        .onAppear {
            // 메뉴바 앱은 팝오버가 열려도 활성 앱이 아니라서 첫 클릭이 버튼에 전달되지 않고 창이 닫힘 → 열릴 때 활성화
            NSApp.activate(ignoringOtherApps: true)
            store.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title2)
                .foregroundStyle(.green)
            Text(store.showSettings ? L("app.settings") : "Usage Pace")
                .font(.title3.weight(.semibold))
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let s = store.snapshot {
            // 1시간 넘게 갱신이 없으면 안내 (데스크톱 앱·웹 사용은 반영되지 않으므로)
            if store.now.timeIntervalSince(s.fetchedAt) > 3600 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text(L("stale.notice", Fmt.relative(s.fetchedAt, now: store.now)))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            }
            if let w = s.session {
                LimitCard(title: L("card.session"), window: w, now: store.now, weekly: false)
            }
            if let w = s.weekly {
                LimitCard(title: L("card.weekly.all"), window: w, now: store.now, weekly: true)
            }
        } else {
            // 아직 데이터 없음: 연결 안 됨 → 연결 버튼, 연결됨 → Claude Code 사용 안내
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: store.connected ? "hourglass" : "link")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.connected ? L("empty.waiting") : L("empty.connect"))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if !store.connected {
                        Button(L("button.connect")) { store.connect() }
                            .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }

        if let e = store.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(e).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let s = store.snapshot {
                    Text(L("footer.updated", Fmt.clock(s.fetchedAt), Fmt.relative(s.fetchedAt, now: store.now)))
                }
                Text(L("footer.source"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Spacer()
            iconButton("arrow.clockwise", help: L("button.refresh")) { store.reload() }
            iconButton("gearshape", help: L("app.settings")) { store.showSettings = true }
            iconButton("power", help: L("button.quit")) { NSApp.terminate(nil) }
        }
        .padding(.top, 2)
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Limit card

struct LimitCard: View {
    let title: String
    let window: LimitWindow
    let now: Date
    let weekly: Bool
    var compact = false

    private var used: Double { window.utilization }
    private var elapsed: Double? { window.elapsedFraction(now: now).map { $0 * 100 } }
    private var diff: Double? { elapsed.map { used - $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(compact ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                if let d = diff { PaceBadge(diff: d) }
            }

            Text(timeLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            MeterRow(label: L("meter.used"), value: used, color: usageColor, marker: elapsed)
            if let e = elapsed {
                MeterRow(label: L("meter.elapsed"), value: e, color: .blue.opacity(0.75), marker: nil)
            }

            if !compact, let p = projection {
                Text(p)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private var timeLine: String {
        guard let reset = window.resetsAt,
              let rem = window.remaining(now: now),
              let el = window.elapsedTime(now: now) else {
            return weekly ? L("card.weekly.notStarted") : L("card.session.notStarted")
        }
        return L("card.timeline",
                 Fmt.duration(el), Fmt.duration(window.length),
                 Fmt.duration(rem), Fmt.resetDate(reset, weekly: weekly))
    }

    /// 지금 속도대로 쓰면 리셋 시점에 몇 %가 될지
    private var projection: String? {
        guard let frac = window.elapsedFraction(now: now), frac > 0.03,
              let start = window.startsAt, used > 0 else { return nil }
        let projected = used / frac
        if projected > 100 {
            let hitAt = start.addingTimeInterval(now.timeIntervalSince(start) * 100 / used)
            return L("card.projection.hit", Fmt.resetDate(hitAt, weekly: weekly))
        }
        return L("card.projection.end", Fmt.pct(projected))
    }

    private var usageColor: Color {
        if let d = diff {
            if d > 15 { return .red }
            if d > 5 { return .orange }
            return .green
        }
        if used >= 90 { return .red }
        if used >= 70 { return .orange }
        return .green
    }
}

struct PaceBadge: View {
    let diff: Double   // 사용% - 경과% (퍼센트 포인트)

    var body: some View {
        let (text, color) = style
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var style: (String, Color) {
        let d = Int(diff.rounded())
        switch diff {
        case ..<(-5): return (L("pace.under", abs(d)), .green)
        case ...5: return (L("pace.on"), .blue)
        case ...15: return (L("pace.fast", d), .orange)
        default: return (L("pace.over", d), .red)
        }
    }
}

struct MeterRow: View {
    let label: String
    let value: Double        // 0~100
    let color: Color
    let marker: Double?      // 0~100, 시간 경과 위치 표시

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
            MeterBar(fraction: value / 100, color: color, marker: marker.map { $0 / 100 })
            Text(Fmt.pct(value))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

struct MeterBar: View {
    let fraction: Double
    let color: Color
    let marker: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let f = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(color).frame(width: f > 0 ? max(w * f, 6) : 0)
                if let m = marker {
                    let x = min(max(w * m, 1), w - 1)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.8))
                        .frame(width: 2, height: 14)
                        .offset(x: x - 1)
                        .help(L("meter.marker.help"))
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 8)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group(L("settings.language"), icon: "globe") {
                Picker("", selection: $store.language) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            group(L("settings.cc"), icon: "terminal") {
                HStack {
                    if store.connected {
                        Label(L("settings.connected"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button(L("button.disconnect")) { store.disconnect() }
                    } else {
                        Button(L("button.connect")) { store.connect() }
                    }
                }
                Text(L("settings.cc.hint"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let e = store.errorMessage {
                    Text(e).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            group(L("settings.menubar")) {
                Picker("", selection: $store.menuWindow) {
                    ForEach(MenuWindow.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Picker("", selection: $store.menuStyle) {
                    ForEach(MenuStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            group(L("settings.general")) {
                Toggle(L("settings.launchAtLogin"), isOn: $store.launchAtLogin)
            }

            HStack(alignment: .bottom) {
                Text(L("about.disclaimer"))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(L("button.done"), action: done).keyboardShortcut(.defaultAction)
            }
        }
        .font(.callout)
    }

    private func group<C: View>(_ title: String, icon: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            content()
        }
    }
}
