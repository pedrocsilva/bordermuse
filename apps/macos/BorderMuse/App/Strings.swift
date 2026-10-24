import Foundation

/// The only app-owned language in v1 is US English, independent of the system UI.
enum Strings {
    static func text(_ key: String) -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: "en_US"), arguments: arguments)
    }
}
