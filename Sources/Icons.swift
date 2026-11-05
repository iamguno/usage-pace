import AppKit
import SwiftUI

/// 앱 아이콘(막대 2개 + 기준선)을 메뉴바·팝오버에서도 쓰기 위한 이미지
enum AppIcons {
    /// 메뉴바용 흑백(템플릿) 아이콘. macOS가 라이트·다크 메뉴바에 맞게 색을 입힘.
    /// 위 막대 = 사용량(진하게) + 남은 부분(옅게), 아래 막대 = 시간 경과, 세로선 = 기준선
    static let menuBar: NSImage = {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            let barH: CGFloat = 5, gap: CGFloat = 3
            let x: CGFloat = 1, width: CGFloat = 16
            let topY = (16 - (barH * 2 + gap)) / 2
            let bottomY = topY + barH + gap
            let used: CGFloat = 0.42, elapsed: CGFloat = 0.62
            let markerX = x + width * elapsed

            func capsule(_ rect: NSRect, alpha: CGFloat) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            }
            // 위 막대: 트랙(옅게) + 사용량(진하게)
            capsule(NSRect(x: x, y: topY, width: width, height: barH), alpha: 0.35)
            capsule(NSRect(x: x, y: topY, width: width * used, height: barH), alpha: 1)
            // 아래 막대: 트랙(옅게) + 시간 경과(진하게)
            capsule(NSRect(x: x, y: bottomY, width: width, height: barH), alpha: 0.35)
            capsule(NSRect(x: x, y: bottomY, width: width * elapsed, height: barH), alpha: 1)
            // 기준선: 주변을 지워서 대비를 준 뒤 선을 그림
            let ctx = NSGraphicsContext.current
            ctx?.compositingOperation = .clear
            NSBezierPath(rect: NSRect(x: markerX - 1.5, y: topY - 1.5, width: 3, height: barH + 3)).fill()
            ctx?.compositingOperation = .sourceOver
            capsule(NSRect(x: markerX - 0.75, y: topY - 1.5, width: 1.5, height: barH + 3), alpha: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Usage Pace"
        return image
    }()

    /// 컬러 앱 아이콘 (번들의 AppIcon.icns)
    static var app: NSImage { NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage() }
}
