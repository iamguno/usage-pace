import Foundation

/// 앱에서 고를 수 있는 언어.
/// 새 언어 추가: case 추가 → tools/translations.py에 열 추가 후 실행 (build.sh가 Resources/*.lproj를 자동 포함)
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en, ko, ja
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case es, fr, de
    case ptBR = "pt-BR"

    var id: String { rawValue }

    /// 각 언어를 그 언어 자체로 표기 (잘못 골라도 다시 찾을 수 있도록)
    var nativeName: String {
        switch self {
        case .system: return L("language.system")
        case .en: return "English"
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ptBR: return "Português (Brasil)"
        }
    }
}

/// 선택한 언어의 .lproj 번들에서 문자열을 찾고, 없으면 영어로 대체합니다.
enum L10n {
    private(set) static var bundle: Bundle = .main
    /// 날짜·기간 포맷에 쓰는 로케일
    private(set) static var locale: Locale = .current
    private(set) static var current: AppLanguage = .system

    private static let english: Bundle = lproj("en") ?? .main
    private static let missing = "\u{1}__missing__"

    static func apply(_ language: AppLanguage) {
        current = language
        if language == .system {
            // 시스템 선호 언어 중 앱이 지원하는 첫 언어 (없으면 영어)
            let code = Bundle.main.preferredLocalizations.first ?? "en"
            bundle = lproj(code) ?? english
            locale = .current
        } else {
            bundle = lproj(language.rawValue) ?? english
            locale = Locale(identifier: language.rawValue)
        }
    }

    static func string(_ key: String) -> String {
        let s = bundle.localizedString(forKey: key, value: missing, table: nil)
        if s != missing { return s }
        return english.localizedString(forKey: key, value: key, table: nil)
    }

    private static func lproj(_ code: String) -> Bundle? {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

/// 번역 문자열. 인자가 있으면 String(format:) 규칙 (%@, %d, %1$@ …)
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.string(key)
    return args.isEmpty ? format : String(format: format, locale: L10n.locale, arguments: args)
}
