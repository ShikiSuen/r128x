import Foundation

extension String {
  public var i18n: String {
    #if canImport(SwiftUI)
    if #available(macOS 12, *) {
      return .init(localized: .init(stringLiteral: self), bundle: .module)
    } else {
      return NSLocalizedString(self, bundle: .module, value: self, comment: "")
    }
    #else
    return self // Fallback for platforms without localization support
    #endif
  }
}

extension TimeInterval {
  func formatted() -> String {
    let minutes = Int(self) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
