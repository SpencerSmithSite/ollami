import Foundation

// Ollami: Heap removed — stub retained for call-site compatibility
@MainActor
class HeapManager {
  static let shared = HeapManager()
  private init() {}

  func initialize() {}
  func identify() {}
  func reset() {}
  func track(_ eventName: String, properties: [String: String]? = nil) {}
}
