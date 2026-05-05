# nvidia340-ubuntu-2404 — NVIDIA 340 on Ubuntu 24.04

English | **[Polski](README.pl.md)**

## TL;DR

- **What it does:** helps install the **`nvidia340`** metapackage from PPA [kda2210/nvidia340](https://launchpad.net/~kda2210/+archive/ubuntu/nvidia340) on **Ubuntu 24.04**, build the **DKMS** module on **6.x** kernels (script-injected **`PRE_BUILD`** fixes), and configure **GRUB**, **X11**, **GTK4 (GSK)**, and the **GNOME Settings** launcher.
- **How to run (shortest path):** `sudo bash install-nvidia340.sh` (interactive) or `sudo bash install-nvidia340.sh --complete-online` after Launchpad/network issues. **Review the script first**; preview: `bash install-nvidia340.sh --dry-run --post-install` (no writes).
- **Limits:** **Xorg** only (not Wayland); **NVIDIA proprietary** driver and a **third-party PPA** — you accept operational risk; on **6.15+** kernels **modpost** may fail — often stay on **6.14** + `apt-mark hold`.

## What this script modifies on your system

Run **`install-nvidia340.sh` only after you understand** the list below.

| Path | Action |
|------|--------|
| `/etc/default/grub` | Backup `*.backup.<timestamp>`; removes `nomodeset`; removes `acpi_backlight=vendor`; optionally sets `acpi_backlight=…` (default **skip**; with `--vaio` default **video**); `update-grub` |
| `/etc/X11/xorg.conf.d/20-nvidia.conf` | Minimal NVIDIA Xorg snippet; **Monitor/Modes 1366×768** only with `--lvds-1366x768` or `--vaio` |
| `/etc/environment` | Backup `*.bak.<timestamp>`; sets `GSK_RENDERER=cairo` |
| `/usr/src/nvidia-legacy-340xx-340.108/dkms.conf` (+ DKMS tree copy) | Backup; appends `PRE_BUILD="fix-nv-stdarg.sh"` |
| `/usr/src/nvidia-legacy-340xx-340.108/fix-nv-stdarg.sh` | **PRE_BUILD** helper (6.x kbuild compatibility) |
| `/usr/src/linux-headers-*/Makefile` | **PRE_BUILD** may **patch** one kernel Makefile line; **`Makefile.bak.<timestamp>`** is created inside PRE_BUILD before `sed` |
| `/etc/modprobe.d/blacklist-nvidia-legacy.conf` | Removed in **`--restore-full`** **only with** `--vaio` |
| `~/.local/share/applications/org.gnome.Settings.desktop` | Override with `LIBGL_ALWAYS_SOFTWARE=1` (when `SUDO_USER` and root) |

**Warnings:** requires **`sudo`**; PPA **`kda2210/nvidia340`** is **not** from Canonical — you trust Launchpad/GPG; **`nvidia340`** implies **NVIDIA proprietary EULA** (accepted at `apt install` time).

## Compatibility (universal vs. `--vaio`)

| | Default (universal) | `--vaio` (case study VPCCW1S1E) |
|---|---------------------|----------------------------------|
| GRUB `acpi_backlight` | **skip** (not appended) | default **video** |
| X11 Monitor 1366×768 | **no** | **yes** |
| Pin `GRUB_DEFAULT` to `TARGET_KERNEL` | no (in `--restore-config` / `--restore-full`) | **yes** |
| Remove `blacklist-nvidia-legacy.conf` | no | in **`--restore-full`** |
| Suggested kernel | 6.8 / 6.11 / 6.14 | **6.14** + `apt-mark hold` (avoid modpost on 6.15+) |

## Universal install

1. PPA and package (or use the interactive script):

```bash
sudo add-apt-repository -y ppa:kda2210/nvidia340
sudo apt-get -o Acquire::ForceIPv4=true update
sudo apt-get -o Acquire::ForceIPv4=true install -y nvidia340
```

2. System configuration:

```bash
sudo bash install-nvidia340.sh --post-install
```

3. Graphical session: **Ubuntu on Xorg**. Reboot: `sudo reboot`.

**Script cheatsheet:** `bash install-nvidia340.sh --help`  
**Network / Launchpad:** `sudo bash install-nvidia340.sh --complete-online`  
**Non-root monitor:** `bash install-nvidia340.sh --monitor-launchpad` — on success may run `sudo bash … --complete-online` if `RUN_COMPLETION=1` and you have **NOPASSWD** (use deliberately).

## Troubleshooting (universal)

- **DKMS / `stdarg.h` / `nvtypes.h` / UVM / timer / workqueue:** `sudo bash install-nvidia340.sh --fix-dkms` — technical background is in the script comments and `make.log` under `/var/lib/dkms/nvidia-legacy-340xx/340.108/build/`.
- **Modpost `__vma_start_write` (6.15+):** consider **holding** **6.14** (`linux-image` / `linux-headers`), then `--fix-dkms`.
- **GTK4 / Nautilus:** `GSK_RENDERER=cairo` (script writes `/etc/environment`).
- **Settings → Displays:** launcher with `LIBGL_ALWAYS_SOFTWARE=1` (`.desktop` override).
- **Launchpad timeouts / missing `nvidia340`:** ForceIPv4, different network/hotspot, offline cache, `--install-local-cache` (requires `.deb` files in `/var/cache/apt/archives` — list is embedded in the script).

## Case study: Sony Vaio VPCCW1S1E

**GeForce GT 230M** laptop: internal **LVDS 1366×768**, **`acpi_backlight=video`**, kernel **6.14.0-27-generic** with **hold**, blacklist removal only on full Vaio restore path.

**Example:**

```bash
sudo bash install-nvidia340.sh --vaio --restore-config
# or full reinstall path:
sudo bash install-nvidia340.sh --vaio --restore-full
```

**Variable:** `TARGET_KERNEL` or `--target-kernel 6.14.0-27-generic`.

## Security & risk

- See **[SECURITY.md](SECURITY.md)** (scope, reporting, out-of-scope).
- There is no `curl | bash` one-liner to fetch this script from the internet — you run a local repo file.

## License

See **[LICENSE](LICENSE)** (MIT) unless the release notes say otherwise.
