import Foundation

public struct HTTPResponse: Equatable, Sendable {
  public init(status: Int, headers: [String: String], body: Data) {
    self.status = status
    self.headers = headers
    self.body = body
  }

  public var status: Int
  public var headers: [String: String]
  public var body: Data
}
