# Security

Report vulnerabilities privately using GitHub's private vulnerability reporting for this repository. Do not post device credentials, database URLs, signing keys, or user data in public issues.

The relay stores credential hashes, never raw device credentials. Production connections require TLS. CI uses disposable local PostgreSQL credentials and does not access production data. Untrusted pull requests never receive deployment or Apple signing secrets.

Release signing/notarization runs only for version tags after successful CI, using the protected `release` environment. Download official packages from this repository's GitHub Releases; verify their checksums. Source builds and CI artifacts are not notarized distribution packages.

Exception: the owner approved v1.0.0 and v1.1.0 as Developer ID-signed **without notarization**.
Apple has not scanned these releases through its notarization service. Their release
notes and installation instructions must disclose that status. If you choose to
trust it, use Apple's app-specific Open Anyway exception; never disable Gatekeeper
or SIP. Automatic release workflows continue to require notarization.
