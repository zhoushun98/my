# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Debian system initialization scripts. The canonical script is `debian_init.sh`, which auto-detects the Debian version at runtime. The three version-specific scripts (`debian11_init.sh`, `debian12_init.sh`, `debian13_init.sh`) are kept for reference but are no longer the primary scripts to maintain.

## Usage

Run with root privileges on a fresh Debian installation:

```bash
sudo ./debian_init.sh
```

The script auto-detects Debian 11/12/13 via `lsb_release -cs` and adjusts behavior accordingly. It interactively prompts for mirror selection (13 options) and SSH key-based login configuration.

## Key Design Decisions

- **Version differences**: Debian 11 (bullseye) uses 3 source lines without `non-free-firmware`; Debian 12+ uses 4 lines including backports and `non-free-firmware`.
- **Idempotency**: `optimize_limits` and `configure_history` guard against duplicate appends using `grep -q` checks.
- **vim path**: Dynamically resolved via `find /usr/share/vim/vim*/defaults.vim` — do not hardcode version numbers.
- **`set -e -o pipefail`**: Both are set; pipeline errors are fatal.
- **`read` calls**: Always followed by `|| true` to prevent `set -e` from exiting on EOF (Ctrl+D).
- **`DEBIAN_FRONTEND=noninteractive`**: Set globally to suppress apt interactive prompts.

## What Each Function Does

| Function | Notes |
|---|---|
| `detect_version` | Sets `CODENAME` and `DEBIAN_VER` globals used by `update_sources` |
| `update_sources` | Writes `/etc/apt/sources.list`; format differs by version |
| `optimize_sysctl` | Writes to `/etc/sysctl.d/99-custom.conf` (overwrites safely) |
| `optimize_limits` | Appends to `/etc/security/limits.conf` + patches `/etc/systemd/system.conf` |
| `configure_bash` | Overwrites `~/.bashrc`; clears `/etc/motd` and `/etc/update-motd.d/` |
| `configure_history` | Appends to `/etc/profile` |

## No Build/Test Process

These are standalone shell scripts with no build, test, or lint processes. Static analysis can be done with `shellcheck debian_init.sh`.
