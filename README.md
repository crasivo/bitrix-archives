📥 1C-Bitrix Archives Mirror
===

[![Manual Publish](https://github.com/crasivo/bitrix-archives/actions/workflows/publish_distro_manual.yaml/badge.svg)](https://github.com/crasivo/bitrix-archives/actions/workflows/publish_distro_manual.yaml)
[![Schedule Publish](https://github.com/crasivo/bitrix-archives/actions/workflows/publish_distros_schedule.yaml/badge.svg)](https://github.com/crasivo/bitrix-archives/actions/workflows/publish_distros_schedule.yaml)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/crasivo/bitrix-archives?style=flat-square&color=orange)
![GitHub Repo size](https://img.shields.io/github/repo-size/crasivo/bitrix-archives?style=flat-square)
![License](https://img.shields.io/github/license/crasivo/bitrix-archives?style=flat-square)

This repository is an independent mirror dedicated to preserving the version history of 1C-Bitrix distributions and service
scripts. These resources are intended for development, testing, or rolling back a product to a specific kernel version.

New [releases](https://github.com/crasivo/bitrix-archives/releases) are checked and published daily via GitHub Actions. Project
launch and initial release date: `Jan 26, 2026`.

> [!NOTE]
> Legacy archives and scripts can be found on the [WayBack Machine](https://web.archive.org).
> To find them, enter the URL https://www.1c-bitrix.ru/download/cms.php or a direct link to a specific archive in the search bar.

### ⚠️ Disclaimer

**Attention!** This repository is NOT an official resource of "1C-Bitrix" LLC.

1. The project author is not an official representative or developer of 1C-Bitrix.
1. All source code within the archives is public and downloaded from the company's official servers (`1c-bitrix.ru`).
1. The author is not responsible for the scripts' performance, potential errors in the distribution code, or any consequences of
   their use (including data loss or financial damages).
1. You use these materials at your own risk.

### ⚖️ Licensing and Demo Mode

1C-Bitrix and Bitrix24 software products are commercial software and are distributed under a license agreement.

1. **Commercial License:** To use the product permanently, you
   must [purchase a license key](https://www.1c-bitrix.ru/buy/products/cms.php).
1. **Demo Mode:** You may use any distribution for evaluation purposes free of charge for 30 days. After this period, the
   product's functionality will be restricted.

## 🚀 Usage

### 📦 Available Editions (Distributions)

The project covers all major editions of 1C-Bitrix products (excluding industry-specific ones). A unique tag is created for each
edition in the format `{distro_code}-{main_version}`, e.g., `start-25.100.300`.

Syncing occurs daily at 03:00 UTC. If the kernel (main) version has not changed, the release is skipped.

Supported Bitrix Site Manager (BUS) editions:

- [x] `start` — Start
- [x] `standard` — Standard
- [x] `small_business` — Small Business
- [x] `business` — Business
- [x] `business_cluster` — Enterprise
- [x] `business_cluster_postgresql` — Enterprise for PostgreSQL

Supported Bitrix24 editions:

- [x] `bitrix24` — Self-hosted Corporate Portal
- [x] `bitrix24_shop` — Online Shop + CRM
- [x] `bitrix24_enterprise` — Enterprise

> [!TIP]
> Every release includes a `manifest.json` file containing technical metadata. It also provides a list of pre-installed modules,
> including their specific versions and build dates.

---

# 🔔 Notifications

New release publication statuses are mirrored in the Telegram chat [@bitrix_archives](https://t.me/bitrix_archives). To provide
basic protection against bots, the channel is private (join via invitation link).

Permanent invite link: https://t.me/+j8k10A_npB1iN2Ey

# 📌 Additional Resources

Useful links:

1. [Official 1C-Bitrix Download Page](https://www.1c-bitrix.ru/download/cms.php)
2. [Change Log for each module](https://dev.1c-bitrix.ru/docs/versions.php)
3. [Installation guide via Bitrix Setup script](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=4891)
4. [Restoring backups via Bitrix Restore script](https://dev.1c-bitrix.ru/learning/course/index.php/lesson.php?COURSE_ID=48&LESSON_ID=6979)

# 📜 License

This project is distributed under the [MIT License](https://en.wikipedia.org/wiki/MIT_License). The full license text is available
in the [LICENSE](LICENSE) file.
