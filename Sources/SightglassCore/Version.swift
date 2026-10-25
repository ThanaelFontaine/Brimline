import Foundation

public enum SightglassVersion {
    /// Must equal the VERSION file at the root of the repository (a test checks it).
    public static let source = "0.1.0"

    /// The version of the running app or command: the Info.plist of Sightglass.app when there is
    /// one (the command lives in Sightglass.app/Contents/Helpers), else `source`.
    public static var current: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return v }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        if let dict = NSDictionary(contentsOf: plist), let v = dict["CFBundleShortVersionString"] as? String { return v }
        return source
    }
}
