# nvidia340-ubuntu-2404 — sterownik NVIDIA 340 na Ubuntu 24.04

**[English](README.md)** | Polski

## TL;DR

- **Co robi:** pomaga zainstalować meta-pakiet **`nvidia340`** z PPA [kda2210/nvidia340](https://launchpad.net/~kda2210/+archive/ubuntu/nvidia340) na **Ubuntu 24.04**, zbudować moduł **DKMS** na jądrach **6.x** (łatki `PRE_BUILD` w skrypcie) oraz skonfigurować **GRUB**, **X11**, **GTK4 (GSK)** i launcher **Ustawień GNOME**.
- **Jak uruchomić (najkrócej):** `sudo bash install-nvidia340.sh` (interaktywnie) albo `sudo bash install-nvidia340.sh --complete-online` po problemach z siecią/Launchpad. **Najpierw przejrzyj kod**; do podglądu: `bash install-nvidia340.sh --dry-run --post-install` (bez zapisów).
- **Ograniczenia:** tylko **Xorg** (nie Wayland); sterownik **własnościowy NVIDIA** i **PPA str trzeciej** — akceptacja ryzyka po Twojej stronie; na jądrach **6.15+** możliwy błąd **modpost** — często sensowne **trzymanie się 6.14** + `apt-mark hold`.

## Co ten skrypt zmienia w systemie

Uruchamiaj **tylko po audycie** `install-nvidia340.sh` i zrozumieniu poniższej listy.

| Ścieżka | Operacja |
|--------|----------|
| `/etc/default/grub` | Backup `*.backup.<timestamp>`; usuwa `nomodeset`; usuwa `acpi_backlight=vendor`; opcjonalnie ustawia `acpi_backlight=…` (domyślnie **skip**; z `--vaio` domyślnie **video**); `update-grub` |
| `/etc/X11/xorg.conf.d/20-nvidia.conf` | Generuje minimalną konfigurację NVIDIA; sekcja **Monitor/Modes 1366×768** tylko z `--lvds-1366x768` lub `--vaio` |
| `/etc/environment` | Backup `*.bak.<timestamp>`; `GSK_RENDERER=cairo` |
| `/usr/src/nvidia-legacy-340xx-340.108/dkms.conf` (+ kopia w drzewie DKMS) | Backup; dopisanie `PRE_BUILD="fix-nv-stdarg.sh"` |
| `/usr/src/nvidia-legacy-340xx-340.108/fix-nv-stdarg.sh` | Skrypt **PRE_BUILD** (łatki pod kbuild 6.x) |
| `/usr/src/linux-headers-*/Makefile` | W ramach **PRE_BUILD** możliwa **edycja** jednej linii (output dla zewnętrznych modułów); backup **`Makefile.bak.<timestamp>`** wykonywany wewnątrz PRE_BUILD przed `sed` |
| `/etc/modprobe.d/blacklist-nvidia-legacy.conf` | Usuwany **tylko** w `--restore-full` **z** flagą `--vaio` |
| `~/.local/share/applications/org.gnome.Settings.desktop` | Override z `LIBGL_ALWAYS_SOFTWARE=1` (gdy `SUDO_USER` i root) |

**Ostrzeżenia:** wymagane **`sudo`**; **PPA `kda2210/nvidia340`** nie jest repozytorium Canonical — zaufanie do klucza/serwera Launchpad po Twojej stronie; instalacja **`nvidia340`** wiąże się z **EULA NVIDIA** (akceptacja przy `apt install`).

## Zgodność (uniwersalne vs. profil Vaio)

| | Uniwersalnie (domyślnie) | Profil `--vaio` (case study VPCCW1S1E) |
|---|--------------------------|----------------------------------------|
| GRUB `acpi_backlight` | **skip** (nie dopisywane) | domyślnie **video** |
| X11 Monitor 1366×768 | **nie** | **tak** |
| Pin `GRUB_DEFAULT` do `TARGET_KERNEL` | nie (`--restore-config` / `--restore-full`) | **tak** |
| Usunięcie `blacklist-nvidia-legacy.conf` | nie | w **`--restore-full`** |
| Zalecane jądro | 6.8 / 6.11 / 6.14 | **6.14** + `apt-mark hold` (uniknięcie modpost 6.15+) |

## Instalacja uniwersalna

1. PPA i pakiet (lub użyj skryptu interaktywnie):

```bash
sudo add-apt-repository -y ppa:kda2210/nvidia340
sudo apt-get -o Acquire::ForceIPv4=true update
sudo apt-get -o Acquire::ForceIPv4=true install -y nvidia340
```

2. Konfiguracja systemowa:

```bash
sudo bash install-nvidia340.sh --post-install
```

3. Sesja graficzna: **Ubuntu on Xorg**. Restart: `sudo reboot`.

**Skróty skryptu:** `bash install-nvidia340.sh --help`  
**Sieć / Launchpad:** `sudo bash install-nvidia340.sh --complete-online`  
**Monitor bez roota:** `bash install-nvidia340.sh --monitor-launchpad` — po sukcesie `curl` może wywołać `sudo bash … --complete-online`, jeśli `RUN_COMPLETION=1` i masz **NOPASSWD** (świadomie).

## Rozwiązywanie problemów (uniwersalne)

- **DKMS / `stdarg.h` / `nvtypes.h` / UVM / timer / workqueue:** `sudo bash install-nvidia340.sh --fix-dkms` — szczegóły techniczne: sekcje poniżej w poprzedniej dokumentacji (log `make.log`, `ccflags-y`, `PRE_BUILD`).
- **Modpost `__vma_start_write` (jądro 6.15+):** rozważ **hold** na **6.14** (`linux-image` / `linux-headers`), potem `--fix-dkms`.
- **GTK4 / Nautilus:** `GSK_RENDERER=cairo` (skrypt ustawia w `/etc/environment`).
- **Ustawienia → Wyświetlacz:** launcher z `LIBGL_ALWAYS_SOFTWARE=1` (override `.desktop`).
- **Timeout Launchpad / brak `nvidia340` w apt:** IPv4, inna sieć/hotspot, cache offline, `--install-local-cache` (wymaga `.deb` w `/var/cache/apt/archives` — lista w skrypcie).

Szczegółowe objawy i logi: zob. angielski [README.md](README.md) (ten sam układ) oraz komentarze w `install-nvidia340.sh`.

## Case study: Sony Vaio VPCCW1S1E

Laptop z **GeForce GT 230M**: wewnętrzny panel **LVDS 1366×768**, sensowne jądro **6.14.0-27-generic** z **hold**, parametr **`acpi_backlight=video`**, usunięcie **blacklisty** legacy w pełnej reinstalacji.

**Przykład:**

```bash
sudo bash install-nvidia340.sh --vaio --restore-config
# lub pełna ścieżka od zera:
sudo bash install-nvidia340.sh --vaio --restore-full
```

**Zmienna:** `TARGET_KERNEL` (np. `export TARGET_KERNEL=6.14.0-27-generic`) lub `--target-kernel 6.14.0-27-generic`.

## Bezpieczeństwo i ryzyko

- Zobacz **[SECURITY.md](SECURITY.md)** (zakres zgłoszeń, out-of-scope).
- Nie ma tu `curl | bash` dla pobierania skryptu z sieci — uruchamiasz lokalny plik repo.

## Podziękowania / atrybucja

To repo bazuje na (i jest mocno inspirowane) pracą opublikowaną przez **kda2210** w projekcie **`nvidia-340-ubuntu-24.04`** (pakiety + poprawki DKMS dla NVIDIA 340.108 na Ubuntu 24.04).  
Referencja upstream: **[kda2210/nvidia-340-ubuntu-24.04](https://github.com/kda2210/nvidia-340-ubuntu-24.04)**.

## Licencja

Projekt: **[LICENSE](LICENSE)** (MIT), o ile nie zaznaczono inaczej w release.

---

*Dokumentacja oparta na rozwiązaniu problemu wewnętrznego wyświetlacza (LVDS) na Ubuntu 24.04 z kartą wymagającą sterownika 340.*
