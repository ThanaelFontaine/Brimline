import Foundation
import Security

/// What the check of Google's signature on `agy` found.
public enum AntigravitySignatureCheck: Equatable, Sendable {
    /// Signed by Google (team and identifier as required), and intact.
    case accepted
    /// No signature at all (a script, a program nobody signed).
    case unsigned
    /// A signature, but not the required one (another team, another identifier, an ad hoc signature).
    case requirementFailed
    /// The signature was found broken, which is also what a file being rewritten looks like (an update of
    /// `agy` in place): the reader looks once more before it refuses.
    case changedDuringCheck
    /// The check could not be made (a file that cannot be read, a system error).
    case unreadable
}

/// Checks the signature of the program, before it is launched. A protocol, so that a test never needs a
/// certificate of Google's, and so that no test reads the real `~/.local/bin/agy`.
public protocol AntigravityCodeChecking: Sendable {
    func checkStatic(at url: URL) -> AntigravitySignatureCheck
    /// For a refusal: whether the team is right and only the identifier differs. Only used to give the
    /// refusal its own `detail`; the card says the same sentence.
    func isOtherIdentifier(at url: URL) -> Bool
}

extension AntigravityCodeChecking {
    public func isOtherIdentifier(at url: URL) -> Bool { false }
}

/// The real check, by Security.framework.
///
/// **The rule:** `agy` is trusted when it carries the Developer ID signature of Google, team
/// `EQHXZ8M8AV` AND identifier `cli` (the team alone would also accept any other program Google signs).
/// Brimline keeps no list of builds: Antigravity updates itself, and a build of Google's, signed as
/// above, is the program the user already runs.
///
/// Deliberately not in the requirement: `notarized` (not documented in Apple's requirement language), and the
/// online revocation check (`kSecCSEnforceRevocationChecks` asks the network; `kSecCSNoNetworkAccess` is set).
public struct SecurityFrameworkCodeChecker: AntigravityCodeChecking {
    /// Google's requirement, exactly. Read from `agy` 1.4.11 (`codesign -d -r-`, 04/11/2026): the Apple
    /// anchor, the Developer ID Application certificate, then Google's team (`EQHXZ8M8AV`), and the identifier `cli`.
    public static let google = "identifier \"cli\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"EQHXZ8M8AV\""

    /// The same requirement without its `identifier` clause.
    static let googleAnyIdentifier = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"EQHXZ8M8AV\""

    public var requirement: String
    /// The requirement a refused program is tried against to tell "right team, other identifier" from the rest
    /// (the same requirement without its identifier). Nil when there is none to try.
    private var withoutIdentifier: String?

    public init(requirement: String = Self.google) {
        self.requirement = requirement
        self.withoutIdentifier = requirement == Self.google ? Self.googleAnyIdentifier : nil
    }

    /// For tests, which have no program signed by Google: any requirement, and its looser form.
    init(requirement: String, withoutIdentifier: String?) {
        self.requirement = requirement
        self.withoutIdentifier = withoutIdentifier
    }

    static let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSStrictValidate | (1 << 29)))
    // 1 << 29 is `kSecCSNoNetworkAccess` (CSCommon.h): the name is not imported into Swift.

    public func checkStatic(at url: URL) -> AntigravitySignatureCheck {
        Self.check(url: url, requirement: requirement)
    }

    public func isOtherIdentifier(at url: URL) -> Bool {
        guard let withoutIdentifier else { return false }
        return Self.check(url: url, requirement: withoutIdentifier) == .accepted
    }

    static func check(url: URL, requirement text: String) -> AntigravitySignatureCheck {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return .unreadable }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return .unreadable }
        return classify(SecStaticCodeCheckValidityWithErrors(code, flags, requirement, nil))
    }

    /// What a status of Security.framework means for the reader (the static check, and the check on the
    /// launched process, which `AntigravityRunFailure.codeRejected` carries).
    public static func classify(_ status: OSStatus) -> AntigravitySignatureCheck {
        switch status {
        case errSecSuccess: return .accepted
        case errSecCSUnsigned: return .unsigned
        case errSecCSReqFailed: return .requirementFailed
        case errSecCSStaticCodeChanged, errSecCSSignatureFailed, errSecCSSignatureInvalid: return .changedDuringCheck
        default: return .unreadable
        }
    }
}
