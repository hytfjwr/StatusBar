# Security Policy

## Plugin System

StatusBar's plugin system loads third-party code as dynamic libraries (`dylib`) at runtime using `dlopen()`. To enable this, the app ships with the `com.apple.security.cs.disable-library-validation` entitlement, which disables Apple's library validation.

This means **any dylib placed in the plugins directory will be loaded and executed with the same privileges as StatusBar itself**.

### Recommendations

- Only install plugins from sources you trust.
- Review plugin source code before installing, when possible.
- Plugins distributed via GitHub Releases should come from verified repositories.
- If a plugin requests unusual permissions or behaves unexpectedly, remove it immediately from `~/Library/Application Support/StatusBar/Plugins/`.

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Preferred**: Use [GitHub's private vulnerability reporting](https://github.com/hytfjwr/macos-status-bar/security/advisories/new) to submit a report directly on the repository.
2. **Alternative**: Email hytfjwr via their GitHub profile contact.

Please do **not** open a public issue for security vulnerabilities.

We will acknowledge receipt within 72 hours and aim to release a fix as soon as practical.
