# Security Policy

## Supported Versions

Only the latest release of MegaBasterd receives security updates.

| Version | Supported |
| ------- | --------- |
| Latest  | Yes       |
| Older   | No        |

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Instead, open a [GitHub Security Advisory](https://github.com/DominicLC/megabasterd/security/advisories/new) so it can be reviewed privately.

Include as much of the following as possible:

- Type of vulnerability (e.g. remote code execution, credential leak, MITM)
- Steps to reproduce
- Affected version(s)
- Potential impact

You can expect an initial response within **7 days**. If the vulnerability is confirmed, a fix will be prioritized for the next release.

## Scope

This project interacts with the MEGA API and handles encrypted file transfers. Areas of particular security sensitivity include:

- AES/RSA cryptographic operations (`CryptTools`)
- Credential storage and master password handling
- The local streaming server (`KissVideoStreamServer`) and proxy server (`MegaProxyServer`)
- Clipboard monitoring (`ClipboardSpy`)
