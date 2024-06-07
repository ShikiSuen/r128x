import Foundation

extension String {
  public var i18n: String {
    .init(localized: .init(stringLiteral: self), bundle: .module)
  }
}
