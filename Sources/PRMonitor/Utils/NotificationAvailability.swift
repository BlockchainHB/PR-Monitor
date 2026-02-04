import Foundation

enum NotificationAvailability {
    static var isAvailable: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }
        if env["XCTestConfigurationFilePath"] != nil {
            return false
        }
        if let bundleType = Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String,
           bundleType == "APPL" {
            return true
        }
        return Bundle.main.bundleURL.pathExtension == "app"
    }
}
