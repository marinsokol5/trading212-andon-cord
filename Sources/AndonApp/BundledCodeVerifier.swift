import Foundation
import Security
import Trading212Core

enum BundledCodeVerifier {
    enum VerificationError: LocalizedError {
        case outsideBundle
        case invalidSignature(OSStatus)
        case signingInformation(OSStatus)
        case signerMismatch

        var errorDescription: String? {
            switch self {
            case .outsideBundle:
                "The bundled t212 command resolved outside Trading 212 Andon Cord."
            case .invalidSignature:
                "The bundled t212 command has an invalid or altered code signature. Reinstall Trading 212 Andon Cord."
            case .signingInformation:
                "The bundled t212 command's signing identity could not be verified."
            case .signerMismatch:
                "The bundled t212 command was not signed by the same identity as Trading 212 Andon Cord."
            }
        }
    }

    static var expectedCLIURL: URL {
        Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/T212CLI.app/Contents/MacOS/t212")
    }

    static func verifyCLI(at url: URL) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let expected = expectedCLIURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard resolved == expected else {
            throw VerificationError.outsideBundle
        }

        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(
            resolved as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard status == errSecSuccess, let staticCode else {
            throw VerificationError.invalidSignature(status)
        }
        status = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            nil
        )
        guard status == errSecSuccess else {
            throw VerificationError.invalidSignature(status)
        }

        var ownCode: SecCode?
        status = SecCodeCopySelf(SecCSFlags(), &ownCode)
        guard status == errSecSuccess, let ownCode else {
            throw VerificationError.signingInformation(status)
        }
        var ownStaticCode: SecStaticCode?
        status = SecCodeCopyStaticCode(ownCode, SecCSFlags(), &ownStaticCode)
        guard status == errSecSuccess, let ownStaticCode else {
            throw VerificationError.signingInformation(status)
        }
        let ownIdentity = try signingIdentity(for: ownStaticCode)
        let cliIdentity = try signingIdentity(for: staticCode)

        #if ANDON_PROD
        guard ownIdentity.teamIdentifier == AppVariant.teamIdentifier,
              cliIdentity.teamIdentifier == AppVariant.teamIdentifier else {
            throw VerificationError.signerMismatch
        }
        #endif

        if let team = ownIdentity.teamIdentifier, !team.isEmpty {
            guard cliIdentity.teamIdentifier == team else {
                throw VerificationError.signerMismatch
            }
        } else {
            // Ad-hoc development signatures intentionally have neither a team
            // identifier nor a leaf certificate. The outer app signature seals
            // this exact helper path, and development cannot contact Live.
            guard cliIdentity.leafCertificate == ownIdentity.leafCertificate else {
                throw VerificationError.signerMismatch
            }
        }
    }

    private struct SigningIdentity {
        let teamIdentifier: String?
        let leafCertificate: Data?
    }

    private static func signingIdentity(for code: SecStaticCode) throws -> SigningIdentity {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard status == errSecSuccess,
              let dictionary = information as? [CFString: Any] else {
            throw VerificationError.signingInformation(status)
        }
        let team = dictionary[kSecCodeInfoTeamIdentifier] as? String
        let certificates = dictionary[kSecCodeInfoCertificates] as? [SecCertificate]
        let leaf = certificates?.first.map { SecCertificateCopyData($0) as Data }
        return SigningIdentity(teamIdentifier: team, leafCertificate: leaf)
    }
}
