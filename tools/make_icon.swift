// Usage Pace 앱 아이콘 렌더러
// 아이콘 다시 만들기: ./tools/make_icon.sh  → Assets/AppIcon.icns
// 직접 실행: make_icon <variant> <out.png> [size]   variant: bars-dark(채택) | rings-dark | rings-light
//
// 개념: 초록 = 사용량, 파랑 = 시간 경과, 흰 눈금 = "지금 시간이면 여기까지 써도 된다"는 기준선

import SwiftUI
import AppKit

let usedFraction = 0.42
let elapsedFraction = 0.62

let green = Color(red: 0.20, green: 0.83, blue: 0.45)
let blue = Color(red: 0.24, green: 0.55, blue: 1.00)

struct IconBackground: View {
    let dark: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 185, style: .continuous)
            .fill(LinearGradient(
                colors: dark
                    ? [Color(red: 0.16, green: 0.20, blue: 0.27), Color(red: 0.06, green: 0.08, blue: 0.11)]
                    : [Color(white: 1.0), Color(red: 0.90, green: 0.92, blue: 0.95)],
                startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(Color.white.opacity(dark ? 0.10 : 0.6), lineWidth: 3)
            )
            .frame(width: 824, height: 824)
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
    }
}

/// 원형 게이지 2개: 바깥 = 시간 경과(파랑), 안쪽 = 사용량(초록), 눈금 = 경과 위치
struct RingsIcon: View {
    let dark: Bool
    var body: some View {
        let track = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
        let marker = dark ? Color.white : Color(white: 0.15)
        ZStack {
            IconBackground(dark: dark)
            // 바깥 링: 시간 경과
            Circle().stroke(track, lineWidth: 70).frame(width: 560, height: 560)
            Circle().trim(from: 0, to: elapsedFraction)
                .stroke(blue, style: StrokeStyle(lineWidth: 70, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 560, height: 560)
            // 안쪽 링: 사용량
            Circle().stroke(track, lineWidth: 70).frame(width: 380, height: 380)
            Circle().trim(from: 0, to: usedFraction)
                .stroke(green, style: StrokeStyle(lineWidth: 70, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 380, height: 380)
            // 기준 눈금: 안쪽 링 위, 시간 경과 각도
            Capsule()
                .fill(marker)
                .frame(width: 16, height: 104)
                .offset(y: -190)
                .rotationEffect(.degrees(360 * elapsedFraction))
        }
        .frame(width: 1024, height: 1024)
    }
}

/// 앱 화면과 같은 막대 2개 + 기준선
struct BarsIcon: View {
    var body: some View {
        let track = Color.white.opacity(0.10)
        let width: CGFloat = 560
        ZStack {
            IconBackground(dark: true)
            VStack(spacing: 70) {
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(green).frame(width: width * usedFraction)
                }
                .frame(width: width, height: 110)
                // 기준선은 레이아웃에 영향 없이 막대 위아래로 살짝 튀어나오게 (앱 화면과 같은 모양)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.white)
                        .frame(width: 18, height: 170)
                        .offset(x: width * elapsedFraction - 9)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(blue).frame(width: width * elapsedFraction)
                }
                .frame(width: width, height: 110)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
enum Main {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: make_icon <rings-dark|rings-light|bars-dark> <out.png> [size]"); exit(1)
        }
        let size = args.count >= 4 ? Double(args[3]) ?? 1024 : 1024
        let view: AnyView
        switch args[1] {
        case "rings-light": view = AnyView(RingsIcon(dark: false))
        case "rings-dark": view = AnyView(RingsIcon(dark: true))
        default: view = AnyView(BarsIcon())   // 채택된 디자인
        }
        let r = ImageRenderer(content: view.frame(width: 1024, height: 1024))
        r.scale = size / 1024
        r.isOpaque = false
        guard let cg = r.cgImage else { print("render failed"); exit(1) }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: args[2]))
    }
}
