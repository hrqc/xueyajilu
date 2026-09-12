import Foundation

public enum AppLanguage: String, CaseIterable, Sendable, Equatable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    public var displayName: String { self == .simplifiedChinese ? "简体中文" : "English" }
}

public enum BPText {
    public static func localized(_ key: String, language: AppLanguage = .simplifiedChinese) -> String {
        let bundle = Bundle.main
        guard let path = bundle.path(forResource: language.rawValue, ofType: "lproj"), let localizedBundle = Bundle(path: path) else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }
}
