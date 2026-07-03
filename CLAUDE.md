# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Linux system initialization scripts. The canonical script is `linux_init.sh`, which auto-detects the distro and version at runtime (Debian 11/12/13, Ubuntu 22.04/24.04/26.04). The older scripts (`debian_init.sh`, `debian11_init.sh`, `debian12_init.sh`, `debian13_init.sh`) are kept for reference but are no longer maintained.

## Usage

Run with root privileges on a fresh installation:

```bash
sudo ./linux_init.sh
```

The script auto-detects the distro via `/etc/os-release` (`ID` + `VERSION_CODENAME`) and adjusts behavior accordingly. It interactively prompts for mirror selection (13 options) and SSH key-based login configuration.

## Key Design Decisions

- **Source format**: Debian 11 and Ubuntu 22.04 use one-line `/etc/apt/sources.list` (any stock DEB822 file gets renamed to `.disabled`); Debian 12+ and Ubuntu 24.04+ use DEB822 format in `/etc/apt/sources.list.d/{debian,ubuntu}.sources` (two stanzas: main+updates+backports and security, with `Signed-By`), and `sources.list` is replaced with a comment-only file to prevent duplicate sources. `SRC_FORMAT` is decided in `detect_version`.
- **Distro differences**: Debian components are `main contrib non-free` (+ `non-free-firmware` on 12+); Ubuntu uses `main restricted universe multiverse`. Ubuntu security lives in the same repo as the main archive (`-security` suite), so mirrors point both at the same URL. Mirror URLs are assembled from a shared `base_url` + `/debian`, `/debian-security`, or `/ubuntu`.
- **Ubuntu non-amd64**: `update_sources` is skipped (official archive and mirrors only carry amd64; other arches live on ports.ubuntu.com with inconsistent mirror paths).
- **SSH drop-in prefix**: `00-hardening.conf`, not `99-`. sshd uses first-match-wins, and Ubuntu cloud images ship `50-cloud-init.conf` with `PasswordAuthentication yes`, which would override a `99-` file. The script also removes any legacy `99-hardening.conf` from older script versions.
- **`NEEDRESTART_MODE=a`**: Exported globally; Ubuntu 22.04+ ships `needrestart`, which would otherwise prompt interactively during upgrades.
- **Idempotency**: `optimize_limits` and `configure_history` guard against duplicate appends using `grep -q` checks.
- **vim path**: Dynamically resolved via `find /usr/share/vim/vim*/defaults.vim` — do not hardcode version numbers.
- **`set -e -o pipefail`**: Both are set; pipeline errors are fatal.
- **`read` calls**: Always followed by `|| true` to prevent `set -e` from exiting on EOF (Ctrl+D).
- **`DEBIAN_FRONTEND=noninteractive`**: Set globally to suppress apt interactive prompts.

## What Each Function Does

| Function | Notes |
|---|---|
| `detect_version` | Sets `DISTRO`, `CODENAME`, `OS_VER`, `SRC_FORMAT` globals from `/etc/os-release` |
| `update_sources` | One-line `sources.list` (Debian 11 / Ubuntu 22.04) or DEB822 `{debian,ubuntu}.sources` + neutralized `sources.list` (Debian 12+ / Ubuntu 24.04+); skipped on non-amd64 Ubuntu |
| `optimize_sysctl` | Writes to `/etc/sysctl.d/99-custom.conf` (overwrites safely) |
| `optimize_limits` | Appends to `/etc/security/limits.conf` + systemd drop-in `/etc/systemd/system.conf.d/99-limits.conf` |
| `configure_bash` | Writes `/etc/profile.d/custom_bash.sh`; clears `/etc/motd` and `/etc/update-motd.d/`; disables Ubuntu Pro apt news |
| `configure_history` | Writes `/etc/profile.d/history.sh` |

## No Build/Test Process

These are standalone shell scripts with no build, test, or lint processes. Static analysis can be done with `shellcheck linux_init.sh`.
