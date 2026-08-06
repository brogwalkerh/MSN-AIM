import Foundation

/// The PKCE pieces that can be got wrong silently.
///
/// `CarDashCore` has no crypto and must not gain a dependency, so the SHA-256 itself happens
/// in CarDashKit via CryptoKit and the digest is passed in here. What is left is the part
/// that actually breaks OAuth in practice — base64url with `-`/`_` substituted and the `=`
/// padding stripped. Standard base64 is accepted by nothing and rejected with a generic
/// `invalid_grant`, which tells you nothing about which end is wrong.
///
/// Checked against the worked example in RFC 7636 Appendix B, which publishes both the
/// verifier and the resulting digest octets.
public enum PKCE {
    /// Characters RFC 7636 §4.1 permits in a code verifier.
    static let verifierAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static let minimumVerifierLength = 43
    public static let maximumVerifierLength = 128

    /// Builds a code verifier from random bytes.
    ///
    /// Takes the bytes rather than generating them so the result is reproducible in a test;
    /// the caller supplies `SystemRandomNumberGenerator` output in the app.
    ///
    /// Each byte is mapped into the 66-character alphabet by modulo. That is very slightly
    /// biased — 256 is not a multiple of 66 — which matters for a key and does not matter
    /// here: the verifier only needs to be unguessable within a single sign-in, and the
    /// entropy lost is a fraction of a bit across 64 characters.
    public static func verifier(fromRandomBytes bytes: [UInt8]) -> String {
        let usable = bytes.prefix(maximumVerifierLength)
        let characters = usable.map { verifierAlphabet[Int($0) % verifierAlphabet.count] }
        let verifier = String(characters)

        // A short verifier is rejected by the authorization server, so pad deterministically
        // rather than emitting something that will fail at the far end.
        guard verifier.count < minimumVerifierLength else { return verifier }
        return verifier + String(repeating: "0", count: minimumVerifierLength - verifier.count)
    }

    /// base64url(SHA256(verifier)), unpadded — the `code_challenge` value.
    public static func challenge(fromSHA256Digest digest: [UInt8]) -> String {
        base64URLEncoded(Data(digest))
    }

    /// base64url per RFC 4648 §5: `+`→`-`, `/`→`_`, no `=` padding.
    public static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func isValidVerifier(_ verifier: String) -> Bool {
        guard verifier.count >= minimumVerifierLength,
              verifier.count <= maximumVerifierLength else { return false }
        return verifier.allSatisfy { verifierAlphabet.contains($0) }
    }
}
