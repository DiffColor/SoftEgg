import Cocoa
import FlutterMacOS

final class SecurityScopedBookmarkChannel: NSObject {
  private static let channelName = "softegg/security_scoped"
  private static let bookmarkPrefix = "softegg.bookmark."
  private static var shared: SecurityScopedBookmarkChannel?

  private let channel: FlutterMethodChannel
  private var activeResources: [String: URL] = [:]

  private init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    super.init()
    channel.setMethodCallHandler(handle)
  }

  static func register(with controller: FlutterViewController) {
    shared = SecurityScopedBookmarkChannel(
      binaryMessenger: controller.engine.binaryMessenger
    )
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let path = call.arguments as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "directory path is required",
          details: nil
        )
      )
      return
    }

    switch call.method {
    case "rememberDirectory":
      rememberDirectory(path: path, result: result)
    case "restoreDirectory":
      restoreDirectory(path: path, result: result)
    case "clearDirectory":
      clearDirectory(path: path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func rememberDirectory(path: String, result: @escaping FlutterResult) {
    let normalizedPath = NSString(string: path).standardizingPath
    let url = URL(fileURLWithPath: normalizedPath, isDirectory: true)

    do {
      let bookmark = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmark, forKey: bookmarkKey(for: normalizedPath))
      _ = startAccessing(url: url)
      result(normalizedPath)
    } catch {
      result(
        FlutterError(
          code: "bookmark_store_failed",
          message: "failed to store security scoped bookmark",
          details: error.localizedDescription
        )
      )
    }
  }

  private func restoreDirectory(path: String, result: @escaping FlutterResult) {
    let normalizedPath = NSString(string: path).standardizingPath
    if let activeUrl = activeResources[normalizedPath] {
      result(activeUrl.path)
      return
    }

    let defaults = UserDefaults.standard
    guard let bookmark = defaults.data(forKey: bookmarkKey(for: normalizedPath)) else {
      result(normalizedPath)
      return
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      let resolvedPath = NSString(string: url.path).standardizingPath
      _ = startAccessing(url: url)
      if isStale || resolvedPath != normalizedPath {
        let refreshedBookmark = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        defaults.removeObject(forKey: bookmarkKey(for: normalizedPath))
        defaults.set(refreshedBookmark, forKey: bookmarkKey(for: resolvedPath))
      }
      result(resolvedPath)
    } catch {
      result(
        FlutterError(
          code: "bookmark_restore_failed",
          message: "failed to restore security scoped bookmark",
          details: error.localizedDescription
        )
      )
    }
  }

  private func clearDirectory(path: String, result: @escaping FlutterResult) {
    let normalizedPath = NSString(string: path).standardizingPath
    if let url = activeResources.removeValue(forKey: normalizedPath) {
      url.stopAccessingSecurityScopedResource()
    }
    UserDefaults.standard.removeObject(forKey: bookmarkKey(for: normalizedPath))
    result(nil)
  }

  @discardableResult
  private func startAccessing(url: URL) -> Bool {
    let normalizedPath = NSString(string: url.path).standardizingPath
    if activeResources[normalizedPath] != nil {
      return true
    }
    let started = url.startAccessingSecurityScopedResource()
    if started {
      activeResources[normalizedPath] = url
    }
    return started
  }

  private func bookmarkKey(for path: String) -> String {
    let data = Data(path.utf8)
    return Self.bookmarkPrefix + data.base64EncodedString()
  }
}
