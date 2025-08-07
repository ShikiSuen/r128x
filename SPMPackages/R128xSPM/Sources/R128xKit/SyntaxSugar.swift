import Foundation

extension String {
  public var i18n: String {
    #if canImport(SwiftUI)
    return .init(localized: .init(stringLiteral: self), bundle: .module)
    #else
    return self // Fallback for platforms without localization support
    #endif
  }
}
