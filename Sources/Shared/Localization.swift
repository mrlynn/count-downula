import Foundation

private final class BundleToken {}

extension Bundle {
    /// The bundle this code is built into: the app, an extension, or the unit test bundle.
    static let countdowncula = Bundle(for: BundleToken.self)
}

/// Text in the person's language, from Resources/Localizable.xcstrings. Plain `String(localized:)`
/// looks in the main bundle, which in tests is the test runner, not the catalog.
func L(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: .countdowncula)
}
