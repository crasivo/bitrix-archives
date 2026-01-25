# Security Policy

## ⚠️ Integrity Disclaimer

This repository is an **automated mirror**. It functions by downloading original archives directly from the official 1C-Bitrix
servers (`1c-bitrix.ru`).

- No modifications are made to the source code of the distributions.
- No third-party patches or "nulling" scripts are applied.
- All files are provided "as-is" for historical and development purposes.

## 🛡️ Verification

To ensure the integrity of the downloaded resources, we provide:

1. **SHA-256 Checksums:** Every release includes a `manifest.json` containing the hash values of the uploaded archives.
2. **Transparency:** The synchronization logic is fully open-source and can be reviewed in
   the [GitHub Actions workflow](./.github/workflows/publish_distros_schedule.yaml).

## 🛡️ Supported Versions

Since this is a mirror, we do not provide security patches for 1C-Bitrix products.

- If you find a security vulnerability in the **1C-Bitrix/Bitrix24 code**, please report it directly to
  the [official Bitrix Security Team](https://www.1c-bitrix.ru/about/security.php).
- We only maintain the security of the **automation scripts** within this repository.

## 🐛 Reporting a Vulnerability

If you discover a security issue related to this repository's automation (e.g., potential for supply chain attacks, insecure
handling of secrets, or suspicious changes in the mirror logic), please follow these steps:

1. **Do not open a public Issue.**
2. Send an email to [crasivodev@gmail.com](mailto:crasivodev@gmail.com) or contact the maintainer via
   Telegram: [@crasivodev](https://t.me/crasivodev).
3. We will acknowledge your report within 48 hours and work on a resolution.

## 🔍 Independent Audit

We encourage users to verify the files downloaded from this mirror against the official sources whenever possible. You can use the
`WayBack Machine` links provided in the README to cross-reference historical data.
