#!/bin/bash

# Skrypt instalacyjny sterowników NVIDIA 340 dla Ubuntu 24.04 (nvidia340-ubuntu-2404)
# Uniwersalny przewodnik + opcjonalny profil Vaio (Sony VPCCW1S1E): flaga --vaio
#
# Wymagania: Ubuntu 24.04 LTS, sudo (wyjątek: --monitor-launchpad, --dry-run).
#
# Użycie (flagi globalne: --vaio, --dry-run, --lvds-1366x768, --target-kernel WER, --acpi-backlight=… — umieść PRZED podkomendą):
#   sudo bash install-nvidia340.sh [--vaio] [--dry-run] …                     — interaktywna instalacja (PPA + nvidia340 + GRUB/X11/GSK)
#   sudo bash install-nvidia340.sh [--vaio] --complete-online                 — apt update/install (ForceIPv4), potem GRUB/X11/GSK
#   sudo bash install-nvidia340.sh [--vaio] [--dry-run] --post-install       — GRUB + X11 + GSK + override Ustawień
#   sudo bash install-nvidia340.sh [--dry-run] --fix-dkms                     — PRE_BUILD / naprawa DKMS
#   sudo bash install-nvidia340.sh [--vaio] [--dry-run] --restore-config     — GRUB/X11/GSK; pin jądra + initramfs tylko z --vaio
#   sudo bash install-nvidia340.sh [--vaio] [--dry-run] --restore-full       — pełna ścieżka (usuń blacklist tylko z --vaio)
#   sudo bash install-nvidia340.sh [--vaio] --install-local-cache [jądro]     — instalacja z /var/cache/apt/archives
#   bash install-nvidia340.sh --monitor-launchpad                             — bez roota; PPA → opcjonalnie sudo --complete-online (NOPASSWD)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_ABS="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${SCRIPT_DIR}/install-nvidia340.sh")"
TARGET_KERNEL="${TARGET_KERNEL:-6.14.0-27-generic}"

# Flagi globalne (ustawiane przez parse_leading_flags przed podkomendą)
FLAG_VAIO=0
DRY_RUN=0
LVDS_1366=0
ACPI_BACKLIGHT=skip
ACPI_EXPLICIT=0
BACKUP_TS="$(date +%Y%m%d_%H%M%S)"
PARSED_CMDLINE=()

# Kolory dla lepszej czytelności
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

validate_target_kernel() {
    local k="${1:?}"
    # np. 6.14.0-27-generic lub 6.8.0-45-hwe-22.04
    if [[ ! "$k" =~ ^[0-9][0-9.+]*-[0-9]+-(generic|hwe-.+)$ ]]; then
        error "Nieprawidłowa wartość --target-kernel: $k (oczekiwano np. 6.14.0-27-generic lub 6.8.0-45-hwe-22.04)"
        exit 1
    fi
}

apply_vaio_profile() {
    if [[ "${FLAG_VAIO:-0}" == "1" ]]; then
        LVDS_1366=1
        if [[ "${ACPI_EXPLICIT:-0}" != "1" ]]; then
            ACPI_BACKLIGHT=video
        fi
    fi
}

# Konsumuje flagi globalne z początku argv; ustawia tablicę PARSED_CMDLINE na resztę.
parse_leading_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h) usage; exit 0 ;;
            --vaio) FLAG_VAIO=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --lvds-1366x768) LVDS_1366=1; shift ;;
            --target-kernel)
                [[ $# -ge 2 ]] || { error "Brak wartości po --target-kernel"; exit 1; }
                validate_target_kernel "$2"
                TARGET_KERNEL="$2"
                shift 2 ;;
            --acpi-backlight=video) ACPI_BACKLIGHT=video; ACPI_EXPLICIT=1; shift ;;
            --acpi-backlight=native) ACPI_BACKLIGHT=native; ACPI_EXPLICIT=1; shift ;;
            --acpi-backlight=vendor) ACPI_BACKLIGHT=vendor; ACPI_EXPLICIT=1; shift ;;
            --acpi-backlight=none) ACPI_BACKLIGHT=none; ACPI_EXPLICIT=1; shift ;;
            --acpi-backlight=skip) ACPI_BACKLIGHT=skip; ACPI_EXPLICIT=1; shift ;;
            --acpi-backlight=*)
                error "Nieznana wartość --acpi-backlight (dozwolone: video|native|vendor|none|skip)"
                exit 1 ;;
            *) break ;;
        esac
    done
    PARSED_CMDLINE=("$@")
}

backup_regular_file() {
    local f="${1:?}"
    [[ -f "$f" ]] || return 0
    local b="${f}.bak.${BACKUP_TS}"
    cp -a -- "$f" "$b"
    info "Kopia zapasowa: $b"
}

# Funkcja do wyświetlania komunikatów
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Funkcja sprawdzająca czy skrypt jest uruchomiony z sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then 
        error "Ten skrypt wymaga uprawnień administratora (sudo)"
        echo "Uruchom: sudo $0"
        exit 1
    fi
}

# W trybie --dry-run podkomendy konfiguracyjne mogą działać bez roota (tylko komunikaty).
require_sudo_or_dry_run() {
    [[ "${DRY_RUN:-0}" == "1" ]] && return 0
    check_sudo
}

# Funkcja sprawdzająca wersję Ubuntu
check_ubuntu_version() {
    if [ ! -f /etc/os-release ]; then
        error "Nie można określić wersji systemu"
        exit 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        error "Ten skrypt jest przeznaczony dla Ubuntu"
        exit 1
    fi
    
    if [ "$VERSION_ID" != "24.04" ]; then
        warning "Ten skrypt jest testowany na Ubuntu 24.04"
        warning "Wykryto: Ubuntu $VERSION_ID"
        read -p "Kontynuować? (t/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Tt]$ ]]; then
            exit 1
        fi
    else
        success "Wykryto Ubuntu 24.04 LTS"
    fi
}

# Funkcja sprawdzająca obecność karty NVIDIA
check_nvidia_card() {
    if ! ( set +o pipefail; lspci | grep -i nvidia >/dev/null ); then
        error "Nie wykryto karty graficznej NVIDIA"
        exit 1
    fi
    
    info "Wykryto kartę graficzną NVIDIA:"
    ( set +o pipefail; lspci | grep -i nvidia )
}

# Naprawa DKMS na jądrach 6.x: sterownik 340.108 z grudnia 2019 (kernel 5.3 / Ubuntu 19.10);
# kbuild i nagłówki w 6.x wymagają PRE_BUILD: nv_stdarg.h (linux/stdarg.h) + ccflags-y (ścieżka include → nvtypes.h).
# DKMS szuka PRE_BUILD w katalogu build (ścieżka względna), skrypt musi być w drzewie źródłowym.
fix_dkms_via_prebuild() {
    local dkms_src="/usr/src/nvidia-legacy-340xx-340.108"
    local dkms_conf="$dkms_src/dkms.conf"
    local prebuild_script="$dkms_src/fix-nv-stdarg.sh"
    [ ! -f "$dkms_conf" ] && { error "Brak $dkms_conf (najpierw: apt install -y nvidia340)"; return 1; }
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] --fix-dkms: zapisałbym $prebuild_script, zbackupowałbym $dkms_conf i Makefile nagłówków, dopisałbym PRE_BUILD, uruchomiłbym dkms install"
        return 0
    fi
    backup_regular_file "$dkms_conf"
    [[ -f "/var/lib/dkms/nvidia-legacy-340xx/340.108/source/dkms.conf" ]] && backup_regular_file "/var/lib/dkms/nvidia-legacy-340xx/340.108/source/dkms.conf"
    info "Instalacja skryptu PRE_BUILD do drzewa źródłowego ($prebuild_script)"
    cat > "$prebuild_script" << 'PREBUILD_EOF'
#!/bin/sh
# DKMS PRE_BUILD: kompatybilność 340.108 (2019, kernel 5.3) z jądrem 6.x; wywołanie z katalogu build
cat > nv_stdarg.h << 'ENDNVSTDARG'
/*
 * SPDX-FileCopyrightText: Copyright (c) 2021 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: MIT
 */

#ifndef _NV_STDARG_H_
#define _NV_STDARG_H_

#if defined(__KERNEL__)
   #include <linux/stdarg.h>
#else
   #include <stdarg.h>
#endif

#endif // _NV_STDARG_H_
ENDNVSTDARG
# Kbuild używa tylko ccflags-y. Pierwsza linia ccflags-y jest przed dodaniem -DNVRM, więc gcc nie dostaje NVRM → brak nv_state_t/rm_resume_smu.
if ! grep -q 'ccflags-y += \$(EXTRA_CFLAGS)' nvidia-modules-common.mk 2>/dev/null; then
  sed -i '/EXTRA_CFLAGS += -Wall -MD/a ccflags-y += \$(EXTRA_CFLAGS)' nvidia-modules-common.mk
fi
# Druga linia ccflags-y po bloku -DNVRM, żeby pełne EXTRA_CFLAGS (z NVRM) trafiło do gcc.
if ! grep -q 'NVRM-ccflags-fix' nvidia-modules-common.mk 2>/dev/null; then
  sed -i '/EXTRA_CFLAGS += -D__KERNEL__ -DMODULE -DNVRM/a # NVRM-ccflags-fix: pełne EXTRA_CFLAGS do ccflags-y/' nvidia-modules-common.mk
  sed -i '/# NVRM-ccflags-fix: pełne EXTRA_CFLAGS do ccflags-y\//a ccflags-y += \$(EXTRA_CFLAGS)' nvidia-modules-common.mk
fi
# UVM/fix 6.x (RCA): -C to symlink (/lib/.../build -> /usr/src/linux-headers-...) => w Makefile jądra CURDIR != abs_srctree
# => filter pusty => output pusty => __sub-make -C w złym katalogu (/usr/src) => Makefile: Nie ma takiego pliku. Fix: realpath(KERNEL_SOURCES).
# UVM-fix 6.x: wstawiamy literalną zrealizowaną ścieżkę jądra (readlink -f) zamiast symlinku, żeby make jądra dostał CURDIR=abs_srctree.
KERNEL_BUILD_RESOLVED=""
for d in /lib/modules/$(uname -r)/build /usr/src/linux-headers-$(uname -r); do
  [ -d "$d" ] && KERNEL_BUILD_RESOLVED=$(readlink -f "$d" 2>/dev/null) && [ -n "$KERNEL_BUILD_RESOLVED" ] && break
done
if [ -n "$KERNEL_BUILD_RESOLVED" ] && ! grep -q "KBUILD_PARAMS += -C $KERNEL_BUILD_RESOLVED" nvidia-modules-common.mk 2>/dev/null; then
  sed -i "/KBUILD_PARAMS += srctree=/d" nvidia-modules-common.mk
  sed -i "s|KBUILD_PARAMS += -C \$(KERNEL_SOURCES) M=\$(PWD)|KBUILD_PARAMS += -C $KERNEL_BUILD_RESOLVED M=\$(PWD)|" nvidia-modules-common.mk
  LINE=$(grep -n "KBUILD_PARAMS += -C $KERNEL_BUILD_RESOLVED M=" nvidia-modules-common.mk | head -1 | cut -d: -f1)
  [ -n "$LINE" ] && sed -i "${LINE}a KBUILD_PARAMS += srctree=$KERNEL_BUILD_RESOLVED" nvidia-modules-common.mk
fi
if ! grep -q 'KBUILD_PARAMS.*srctree' nvidia-modules-common.mk 2>/dev/null; then
  sed -i '/KBUILD_PARAMS += -C \$(KERNEL_SOURCES) M=\$(PWD)/a KBUILD_PARAMS += srctree=\$(KERNEL_SOURCES)' nvidia-modules-common.mk
fi
# Kernel 6.17: gdy KBUILD_EXTMOD, warunek filter(CURDIR,objtree,abs_srctree) bywa pusty => output pusty => abs_output=CURDIR (/usr/src) => __sub-make -C /usr/src => błąd.
# Fix: dla modułów zewn. zawsze output := $(KBUILD_EXTMOD), żeby __sub-make działał w katalogu modułu (nie nadpisujemy Makefile jądra).
KMF="/usr/src/linux-headers-$(uname -r)/Makefile"
if [ -f "$KMF" ]; then
  ts_bak=$(date +%Y%m%d_%H%M%S)
  cp -a "$KMF" "${KMF}.bak.${ts_bak}" 2>/dev/null || true
fi
if [ -f "$KMF" ] && grep -q 'filter \$(CURDIR),\$(objtree) \$(abs_srctree)' "$KMF" 2>/dev/null; then
  sed -i 's|^[[:space:]]*output := $(or $(KBUILD_EXTMOD_OUTPUT),$(if $(filter $(CURDIR),$(objtree) $(abs_srctree)),$(KBUILD_EXTMOD)))|    output := $(or $(KBUILD_EXTMOD_OUTPUT),$(KBUILD_EXTMOD))|' "$KMF"
fi
# UVM: KBUILD_EXTMOD=$(RM_OUT_DIR) to ścieżka względna (..) => w jądrze realpath(..)=/usr/src => make -C /usr/src. Fix: po "cd $(RM_OUT_DIR)" przekazać KBUILD_EXTMOD=$$(pwd).
if [ -f uvm/Makefile ] && grep -q 'KBUILD_EXTMOD=\$(RM_OUT_DIR)' uvm/Makefile 2>/dev/null; then
  sed -i 's|KBUILD_EXTMOD=\$(RM_OUT_DIR)|KBUILD_EXTMOD=\$\$(pwd)|g' uvm/Makefile
fi
# Kernel 6.6+: del_timer_sync usunięte, jest timer_delete_sync (RCA: implicit declaration w nv.c:2459).
if ! grep -q 'del_timer_sync.*timer_delete_sync' nv-linux.h 2>/dev/null; then
  sed -i '/#include <linux\/timer.h>/a\
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,6,0)\
#define del_timer_sync timer_delete_sync\
#endif' nv-linux.h
fi
# Kernel 6.x: flush_scheduled_work() wywołuje __warn_flushing_systemwide_wq → -Wattribute-warning → błąd (RCA: nv-linux.h:1706).
if ! grep -q 'NV_TASKQUEUE_FLUSH_6x_compat' nv-linux.h 2>/dev/null; then
  cat > .flush_compat_6x.txt << 'FLUSHCOMPAT'
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,5,0)
/* NV_TASKQUEUE_FLUSH_6x_compat: unikaj -Wattribute-warning (system-wide WQ) */
#undef NV_TASKQUEUE_FLUSH
#define NV_TASKQUEUE_FLUSH() do { \
    _Pragma("GCC diagnostic push"); \
    _Pragma("GCC diagnostic ignored \"-Wattribute-warning\""); \
    flush_scheduled_work(); \
    _Pragma("GCC diagnostic pop"); \
} while(0)
#endif
FLUSHCOMPAT
  sed -i '/flush_scheduled_work();$/r .flush_compat_6x.txt' nv-linux.h
  rm -f .flush_compat_6x.txt
fi
PREBUILD_EOF
    chmod 755 "$prebuild_script"
    # DKMS kopiuje do build z $dkms_tree/.../source i czyta dkms.conf stamtąd – skrypt i PRE_BUILD muszą być w source
    # Ważne: usuń starą linię PRE_BUILD (np. /usr/local/bin/...), bo DKMS traktuje ją jako ścieżkę względną do build/
    local dkms_src_dir="/var/lib/dkms/nvidia-legacy-340xx/340.108/source"
    for f in "$dkms_conf" "$dkms_src_dir/dkms.conf"; do
        [ -f "$f" ] && sed -i '/^PRE_BUILD=/d' "$f"
    done
    info "Zastąpiono PRE_BUILD w dkms.conf (ścieżka względna fix-nv-stdarg.sh)"
    if [ -d "$dkms_src_dir" ]; then
        cp "$prebuild_script" "$dkms_src_dir/fix-nv-stdarg.sh"
        chmod 755 "$dkms_src_dir/fix-nv-stdarg.sh"
        echo 'PRE_BUILD="fix-nv-stdarg.sh"' >> "$dkms_src_dir/dkms.conf"
        info "Skrypt PRE_BUILD zapisany w $dkms_src_dir (+ dkms.conf)"
    fi
    echo 'PRE_BUILD="fix-nv-stdarg.sh"' >> "$dkms_conf"
    info "Dodano PRE_BUILD do $dkms_conf"
    [ -x "$prebuild_script" ] || { error "Skrypt PRE_BUILD nie jest wykonywalny: $prebuild_script"; return 1; }
    info "Budowanie modułu DKMS nvidia-legacy-340xx/340.108..."
    if ! dkms install nvidia-legacy-340xx/340.108; then
        local make_log="/var/lib/dkms/nvidia-legacy-340xx/340.108/build/make.log"
        error "DKMS install nie powiódł się."
        if [ -f "$make_log" ]; then
            echo ""
            info "Ostatnie linie make.log (błąd kompilacji):"
            tail -n 25 "$make_log" | sed 's/^/  | /'
            echo ""
            info "Pełny log: $make_log"
        fi
        return 1
    fi
    success "Moduł DKMS zbudowany."
    info "Dokończenie konfiguracji pakietów..."
    dpkg --configure -a && success "Konfiguracja pakietów zakończona." || return 1
    return 0
}

# Funkcja wykrywająca BusID karty graficznej
detect_busid() {
    # Wykryj BusID karty NVIDIA (VGA, 3D lub Display controller)
    # W podpowłoce wyłączamy pipefail — pojedyncze grep bez trafień nie ma przerywać skryptu.
    local busid
    busid=$(
        set +o pipefail
        lspci | grep -iE "VGA|3D|Display" | grep -i nvidia | head -1 | awk '{print $1}' | sed 's/\./:/g' | sed 's/^/PCI:/'
    )
    
    if [ -z "$busid" ]; then
        busid=$(
            set +o pipefail
            lspci -n | grep -i "10de" | grep -iE "030[0-3]" | head -1 | awk '{print $1}' | sed 's/\./:/g' | sed 's/^/PCI:/'
        )
    fi
    
    if [ -z "$busid" ]; then
        error "Nie można wykryć BusID karty graficznej"
        error "Sprawdź ręcznie: lspci | grep -i nvidia"
        exit 1
    fi
    
    echo "$busid"
}

# Funkcja konfiguracji GRUB
configure_grub() {
    info "Konfiguracja GRUB (acpi_backlight=${ACPI_BACKLIGHT})..."
    
    local grub_file="/etc/default/grub"
    local backup_file="${grub_file}.backup.${BACKUP_TS}"
    
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] Skopiowałbym $grub_file → $backup_file; usunąłbym nomodeset; ustawiłbym acpi (tryb: ${ACPI_BACKLIGHT}); update-grub"
        return 0
    fi
    
    cp "$grub_file" "$backup_file"
    success "Utworzono kopię zapasową GRUB: $backup_file"
    
    if grep -q "nomodeset" "$grub_file"; then
        info "Usuwanie parametru 'nomodeset' z GRUB..."
        sed -i 's/ nomodeset//g' "$grub_file"
        sed -i 's/nomodeset //g' "$grub_file"
        sed -i 's/nomodeset$//g' "$grub_file"
        sed -i 's/^nomodeset //g' "$grub_file"
    fi
    
    if grep -q "acpi_backlight=vendor" "$grub_file"; then
        info "Usuwanie parametru 'acpi_backlight=vendor' z GRUB..."
        sed -i 's/ acpi_backlight=vendor//g' "$grub_file"
        sed -i 's/acpi_backlight=vendor //g' "$grub_file"
        sed -i 's/acpi_backlight=vendor$//g' "$grub_file"
        sed -i 's/^acpi_backlight=vendor //g' "$grub_file"
    fi
    
    # Usuń dowolne acpi_backlight=* z GRUB_CMDLINE_LINUX_DEFAULT, potem (jeśli != skip) dopisz wybrany parametr jądra
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file"; then
        local current_line
        current_line="$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" 2>/dev/null | head -1 | cut -d'"' -f2 || true)"
        current_line="$(echo "$current_line" | sed -E 's/[[:space:]]*acpi_backlight=[^[:space:]]*//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')"
        if [[ "${ACPI_BACKLIGHT}" != "skip" ]]; then
            current_line="${current_line} acpi_backlight=${ACPI_BACKLIGHT}"
            current_line="$(echo "$current_line" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')"
            info "Ustawiam GRUB_CMDLINE_LINUX_DEFAULT (acpi_backlight=${ACPI_BACKLIGHT})..."
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${current_line}\"|" "$grub_file"
        else
            info "acpi_backlight=skip — nie dopisuję acpi_backlight=* (czyszczę pozostałości w linii domyślnej)"
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${current_line}\"|" "$grub_file"
        fi
    else
        if [[ "${ACPI_BACKLIGHT}" != "skip" ]]; then
            info "Dodawanie linii GRUB_CMDLINE_LINUX_DEFAULT z acpi_backlight=${ACPI_BACKLIGHT}..."
            sed -i '$a GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi_backlight='"${ACPI_BACKLIGHT}"'"' "$grub_file"
        fi
    fi
    
    if update-grub; then
        success "GRUB został zaktualizowany"
    else
        error "Błąd podczas aktualizacji GRUB"
        exit 1
    fi
}

# Funkcja tworzenia konfiguracji X11 (Monitor/Modes tylko z --lvds-1366x768 lub --vaio)
create_x11_config() {
    info "Tworzenie konfiguracji X11 (LVDS 1366×768: $([[ "${LVDS_1366:-0}" == "1" ]] && echo tak || echo nie))..."
    
    local busid
    busid="$(detect_busid)"
    info "Wykryty BusID: $busid"
    
    local xorg_dir="/etc/X11/xorg.conf.d"
    local xorg_file="${xorg_dir}/20-nvidia.conf"
    
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] Utworzyłbym $xorg_file (BusID=$busid, sekcja Monitor: $([[ "${LVDS_1366:-0}" == "1" ]] && echo tak || echo nie))"
        return 0
    fi
    
    mkdir -p "$xorg_dir"
    
    if [[ "${LVDS_1366:-0}" == "1" ]]; then
        cat > "$xorg_file" << EOF
Section "Files"
    ModulePath "/usr/lib/nvidia/legacy-340xx/xorg"
    ModulePath "/usr/lib/xorg/modules"
EndSection

Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "$busid"
EndSection

Section "Monitor"
    Identifier     "LVDS Monitor"
    Option         "PreferredMode" "1366x768"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "NVIDIA Card"
    Monitor        "LVDS Monitor"
    DefaultDepth    24
    Option         "UseDisplayDevice" "DFP-0"
    SubSection     "Display"
        Depth       24
        Modes      "1366x768" "1024x768" "800x600" "640x480"
    EndSubSection
EndSection
EOF
    else
        cat > "$xorg_file" << EOF
Section "Files"
    ModulePath "/usr/lib/nvidia/legacy-340xx/xorg"
    ModulePath "/usr/lib/xorg/modules"
EndSection

Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "$busid"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "NVIDIA Card"
    DefaultDepth    24
EndSection
EOF
    fi
    
    success "Utworzono konfigurację X11: $xorg_file"
    info "BusID w konfiguracji: $busid"
}

# Nadpisanie launchera Ustawień: panel „Wyświetlacz” ładuje GL przez libepoxy (poza GSK);
# nvidia-340 nie udostępnia GL_ARB_sampler_objects — bez tego gnome-control-center się wywala.
configure_gnome_settings_desktop_override() {
    if [ -z "${SUDO_USER:-}" ] || [ "$(id -u)" -ne 0 ]; then
        info "Pomijam ~/.local/share/applications/org.gnome.Settings.desktop (brak SUDO_USER lub nie root)."
        info "Po instalacji skopiuj szablon z dokumentacji lub uruchom ponownie: sudo -E bash $0 --post-install"
        return 0
    fi
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        local uh_d
        uh_d="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
        info "[DRY-RUN] Utworzyłbym ${uh_d:-\$HOME}/.local/share/applications/org.gnome.Settings.desktop (LIBGL_ALWAYS_SOFTWARE=1)"
        return 0
    fi
    local uh
    uh="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    if [ -z "$uh" ] || [ ! -d "$uh" ]; then
        warning "Nie znaleziono katalogu domowego dla SUDO_USER=$SUDO_USER — pomijam override Ustawień."
        return 0
    fi
    install -d -o "$SUDO_USER" -g "$SUDO_USER" "$uh/.local/share/applications"
    local desk="$uh/.local/share/applications/org.gnome.Settings.desktop"
    cat >"$desk" << 'EOF'
[Desktop Entry]
Name=Settings
Icon=org.gnome.Settings
Exec=env LIBGL_ALWAYS_SOFTWARE=1 gnome-control-center
Terminal=false
Type=Application
StartupNotify=true
Categories=GNOME;GTK;Settings;
OnlyShowIn=GNOME;
Keywords=Preferences;Settings;
X-Purism-FormFactor=Workstation;Mobile;
X-Ubuntu-Gettext-Domain=gnome-control-center-2.0
EOF
    chown "$SUDO_USER:$SUDO_USER" "$desk"
    chmod 644 "$desk"
    success "Utworzono override Ustawień (LIBGL_ALWAYS_SOFTWARE=1): $desk"
}

# Funkcja konfiguracji GSK_RENDERER (GTK4 / GSK — Nautilus, większość aplikacji GTK4)
configure_gsk_renderer() {
    info "Konfiguracja GSK_RENDERER=cairo (GTK4) + override Ustawień GNOME..."
    
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] Edytowałbym /etc/environment (GSK_RENDERER=cairo) + override org.gnome.Settings.desktop"
        configure_gnome_settings_desktop_override
        return 0
    fi
    
    if [[ -f /etc/environment ]]; then
        backup_regular_file /etc/environment
    fi
    
    if grep -q '^GSK_RENDERER=gl$' /etc/environment 2>/dev/null; then
        sed -i 's/^GSK_RENDERER=gl$/GSK_RENDERER=cairo/' /etc/environment
        success "Zaktualizowano /etc/environment: GSK_RENDERER gl → cairo"
    elif ! grep -q '^GSK_RENDERER=' /etc/environment 2>/dev/null; then
        echo 'GSK_RENDERER=cairo' >> /etc/environment
        success "Dodano GSK_RENDERER=cairo do /etc/environment"
    else
        info "GSK_RENDERER już jest w /etc/environment (bez zmiany na siłę)"
    fi
    
    info "GSK_RENDERER=cairo: renderer sceny GTK4 bez wymogu GL_ARB_sampler_objects (nvidia-340)."
    info "Ustawienia (panel Wyświetlacz): dodatkowo LIBGL_ALWAYS_SOFTWARE=1 w launcherze (override .desktop)."
    configure_gnome_settings_desktop_override
    warning "Wymagany restart lub pełne wylogowanie, aby zmiany w /etc/environment i .desktop zaczęły działać."
}

# Funkcja weryfikacji instalacji
verify_installation() {
    info "Weryfikacja instalacji..."
    
    echo
    info "Sprawdzanie modułu jądra..."
    if ( set +o pipefail; lsmod | grep -q nvidia ); then
        success "Moduł nvidia jest załadowany"
        ( set +o pipefail; lsmod | grep nvidia )
    else
        warning "Moduł nvidia nie jest załadowany (może być normalne przed restartem)"
    fi
    
    echo
    info "Sprawdzanie sterownika..."
    if ( set +o pipefail; lspci -k | grep -A3 VGA | grep -q "nvidia" ); then
        success "Sterownik nvidia jest aktywny"
        ( set +o pipefail; lspci -k | grep -A3 VGA )
    else
        warning "Sterownik nvidia może nie być aktywny (wymagany restart)"
    fi
    
    echo
    info "Sprawdzanie wersji sterownika..."
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi || warning "nvidia-smi nie może się wykonać (może być normalne przed restartem)"
    else
        warning "nvidia-smi nie jest dostępne"
    fi
    
    echo
    info "Sprawdzanie statusu DKMS..."
    ( set +o pipefail; dkms status | grep nvidia ) || warning "DKMS może nie być jeszcze zbudowany"
}

usage() {
    cat << 'USAGE_EOF'
install-nvidia340.sh — NVIDIA 340.108 / Ubuntu 24.04 (nvidia340-ubuntu-2404)

Flagi globalne (PRZED podkomendą): --vaio  --dry-run  --lvds-1366x768
  --target-kernel WER   (np. 6.14.0-27-generic lub 6.8.0-45-hwe-22.04)
  --acpi-backlight=video|native|vendor|none|skip   (domyślnie skip; z --vaio domyślnie video)

  sudo bash install-nvidia340.sh [--vaio] …                     interaktywna instalacja (PPA + pakiet + konfiguracja)
  sudo bash install-nvidia340.sh [--vaio] --complete-online     apt (IPv4), potem konfiguracja
  sudo bash install-nvidia340.sh [--vaio] [--dry-run] --post-install   GRUB / X11 / GSK / override Ustawień
  sudo bash install-nvidia340.sh [--dry-run] --fix-dkms          naprawa DKMS (PRE_BUILD)
  sudo bash install-nvidia340.sh [--vaio] [--dry-run] --restore-config   GRUB/X11/GSK; pin jądra tylko z --vaio
  sudo bash install-nvidia340.sh [--vaio] [--dry-run] --restore-full     kernel + PPA + nvidia340; bez --vaio nie usuwamy blacklisty
  sudo bash install-nvidia340.sh [--vaio] --install-local-cache [jądro]   z /var/cache/apt/archives
  bash install-nvidia340.sh --monitor-launchpad   bez roota; po sukcesie curl: notify + opcjonalnie sudo --complete-online (RUN_COMPLETION=1; NOPASSWD)

Zmienne środowiskowe: TARGET_KERNEL, CHECK_URL, INTERVAL_SEC, LOG_DIR, RUN_COMPLETION, SUDO_REFRESH, itd.
Ostrzeżenie: RUN_COMPLETION=1 z NOPASSWD uruchamia sudo bez pytania — używaj świadomie.
USAGE_EOF
}

# Porządki: pliki .bak w sources.list.d powodują ostrzeżenia apt
archive_bad_apt_sources() {
    [[ "${DRY_RUN:-0}" == "1" ]] && return 0
    local d=/root/vaio-apt-sources-archive
    mkdir -p "$d"
    shopt -s nullglob
    local f
    for f in /etc/apt/sources.list.d/*.bak*; do
        [[ -f "$f" ]] || continue
        mv "$f" "$d/$(basename "$f").$(date +%s)" && info "Przeniesiono do $d: $f"
    done
    shopt -u nullglob
}

# Domyślny wpis GRUB → konkretne jądro (Vaio / kernel hold) — tylko z --vaio
vaio_set_grub_default_kernel() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] Ustawiłbym GRUB_DEFAULT na jądro ${TARGET_KERNEL}"
        return 0
    fi
    local grub_file=/etc/default/grub
    local menu="Advanced options for Ubuntu>Ubuntu, with Linux ${TARGET_KERNEL}"
    if grep -qF "Ubuntu, with Linux ${TARGET_KERNEL}" /boot/grub/grub.cfg 2>/dev/null; then
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="'"${menu}"'"/' "$grub_file"
        info "GRUB_DEFAULT=$menu"
        grub-set-default "${menu}" 2>/dev/null || true
        update-grub || true
    else
        warning "Brak wpisu menu dla ${TARGET_KERNEL} w grub.cfg — zainstaluj linux-image-${TARGET_KERNEL}"
    fi
}

vaio_update_initramfs_target_kernel() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] Uruchomiłbym update-initramfs -u -k ${TARGET_KERNEL}"
        return 0
    fi
    update-initramfs -u -k "${TARGET_KERNEL}" 2>/dev/null || update-initramfs -u -k all || true
}

# --- Podkomendy (scalone z restore-nvidia-internal-display.sh, complete-*.sh, local-cache, monitor) ---

cmd_complete_online() {
    require_sudo_or_dry_run
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] --complete-online: apt install nvidia340 + configure_grub/create_x11/gsk (bez zapisu)"
        configure_grub
        create_x11_config
        configure_gsk_renderer
        return 0
    fi
    export DEBIAN_FRONTEND=noninteractive
    local APT_OPTS=(-o Acquire::ForceIPv4=true)
    info "apt-get update (ForceIPv4)..."
    apt-get "${APT_OPTS[@]}" update -qq
    if ! apt-cache show nvidia340 >/dev/null 2>&1; then
        error "Pakiet nvidia340 niewidoczny dla apt — indeks PPA się nie pobrał (sieć / Launchpad)."
        echo "  Szczegóły: README.md (timeout Launchpad)" >&2
        exit 1
    fi
    info "apt-get install -y nvidia340..."
    apt-get "${APT_OPTS[@]}" install -y nvidia340
    if ! ( set +o pipefail; dkms status 2>/dev/null | grep -qE 'nvidia-legacy-340xx.*installed' ); then
        info "DKMS nie installed — uruchamiam --fix-dkms..."
        fix_dkms_via_prebuild || true
        dpkg --configure -a || true
    fi
    configure_grub
    create_x11_config
    configure_gsk_renderer
    success "Gotowe. Zrestartuj system (Ubuntu on Xorg przy wyborze sesji)."
}

cmd_restore_config() {
    require_sudo_or_dry_run
    export DEBIAN_FRONTEND=noninteractive
    archive_bad_apt_sources
    if ! dpkg -l 2>/dev/null | grep -q '^ii.*nvidia-legacy-340xx-driver'; then
        warning "Pakiet nvidia-legacy-340xx-driver nie jest zainstalowany."
        warning "Z siecią do Launchpad: sudo apt-get update && sudo apt-get install -y nvidia340"
    fi
    configure_grub
    create_x11_config
    if [[ "${FLAG_VAIO:-0}" == "1" ]]; then
        vaio_set_grub_default_kernel
        vaio_update_initramfs_target_kernel
    else
        info "Bez --vaio: pomijam pin GRUB_DEFAULT i update-initramfs dla ${TARGET_KERNEL}"
    fi
    configure_gsk_renderer
    success "Konfiguracja zakończona. sudo reboot"
}

cmd_restore_full() {
    require_sudo_or_dry_run
    export DEBIAN_FRONTEND=noninteractive
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        info "[DRY-RUN] --restore-full: pomijam apt/kernel/PPA; symulacja tylko configure_*"
        configure_grub
        create_x11_config
        if [[ "${FLAG_VAIO:-0}" == "1" ]]; then
            vaio_set_grub_default_kernel
            vaio_update_initramfs_target_kernel
        fi
        configure_gsk_renderer
        success "[DRY-RUN] Koniec symulacji --restore-full"
        return 0
    fi
    if [[ "${FLAG_VAIO:-0}" == "1" ]]; then
        info "[1/8] Usuwanie blacklisty nvidia (--vaio)..."
        if [[ "${DRY_RUN:-0}" == "1" ]]; then
            info "[DRY-RUN] Usunąłbym /etc/modprobe.d/blacklist-nvidia-legacy.conf"
        else
            rm -f /etc/modprobe.d/blacklist-nvidia-legacy.conf
        fi
    else
        info "[1/8] Bez --vaio: pomijam usuwanie blacklist-nvidia-legacy.conf"
    fi

    info "[2/8] Instalacja kernela ${TARGET_KERNEL}..."
    apt-get update -qq
    apt-get install -y -qq "linux-image-${TARGET_KERNEL}" "linux-headers-${TARGET_KERNEL}" || {
        error "Brak linux-image-${TARGET_KERNEL}"
        exit 1
    }
    apt-get install -y -qq "linux-modules-extra-${TARGET_KERNEL}" 2>/dev/null || true

    archive_bad_apt_sources

    info "[3/8] Włączenie PPA kda2210/nvidia340..."
    if [[ -f /etc/apt/sources.list.d/kda2210-ubuntu-nvidia340-noble.sources ]]; then
        sed -i 's/^Enabled: no/Enabled: yes/' /etc/apt/sources.list.d/kda2210-ubuntu-nvidia340-noble.sources 2>/dev/null || true
    else
        add-apt-repository -y ppa:kda2210/nvidia340
    fi

    if ! apt-get update -qq -o Acquire::Retries=5 2>/dev/null; then
        warning "apt-get update z błędami (często PPA/Launchpad)."
    fi

    info "[4/8] Instalacja nvidia340..."
    if apt-get install -y -qq nvidia340; then
        :
    elif dpkg -l 2>/dev/null | grep -q '^ii.*nvidia-legacy-340xx-driver'; then
        info "nvidia340 z apt nie działa, ale sterownik legacy jest — kontynuuję."
    else
        error "Nie udało się zainstalować nvidia340 (np. timeout Launchpad). Hotspot → apt update/install → sudo bash $0 --restore-config"
        exit 1
    fi

    configure_grub
    create_x11_config
    if [[ "${FLAG_VAIO:-0}" == "1" ]]; then
        vaio_set_grub_default_kernel
        vaio_update_initramfs_target_kernel
    else
        info "Bez --vaio: pomijam pin GRUB_DEFAULT i update-initramfs dla ${TARGET_KERNEL}"
    fi
    configure_gsk_renderer
    success "Zrobione. sudo reboot — potem: nvidia-smi; lspci -k | grep -A3 VGA"
}

cmd_install_local_cache() {
    check_sudo
    export DEBIAN_FRONTEND=noninteractive
    local KERN="${1:-${TARGET_KERNEL}}"
    local C=/var/cache/apt/archives
    info "Instalacja z $C, DKMS dla kernela: $KERN"
    apt-get update -qq -o Acquire::Retries=3 || true

    local PKGS=(
        "$C/nvidia-support_20250511_amd64.deb"
        "$C/nvidia-kernel-common_20250511_amd64.deb"
        "$C/nvidia-modprobe_535.54.03-1_amd64.deb"
        "$C/glx-diversions_1.2.3_amd64.deb"
        "$C/glx-alternative-mesa_1.2.3_amd64.deb"
        "$C/glx-alternative-nvidia_1.2.3_amd64.deb"
        "$C/nvidia-legacy-340xx-alternative_340.108-26_amd64.deb"
        "$C/nvidia-legacy-340xx-kernel-support_340.108-26_amd64.deb"
        "$C/nvidia-legacy-340xx-kernel-dkms_340.108-26_amd64.deb"
        "$C/libnvidia-legacy-340xx-cfg1_340.108-26_amd64.deb"
        "$C/libnvidia-legacy-340xx-eglcore_340.108-26_amd64.deb"
        "$C/libnvidia-legacy-340xx-glcore_340.108-26_amd64.deb"
        "$C/libnvidia-legacy-340xx-ml1_340.108-26_amd64.deb"
        "$C/libnvidia-legacy-340xx-cuda1_340.108-26_amd64.deb"
        "$C/libnvidia-legacy-340xx-encode1_340.108-26_amd64.deb"
        "$C/libnvidia-legacy-340xx-nvcuvid1_340.108-26_amd64.deb"
        "$C/libegl1-nvidia-legacy-340xx_340.108-26_amd64.deb"
        "$C/libgles1-nvidia-legacy-340xx_340.108-26_amd64.deb"
        "$C/libgles2-nvidia-legacy-340xx_340.108-26_amd64.deb"
        "$C/libgl1-nvidia-legacy-340xx-glx_340.108-26_amd64.deb"
        "$C/nvidia-legacy-340xx-driver-libs_340.108-26_amd64.deb"
        "$C/nvidia-legacy-340xx-driver-bin_340.108-26_amd64.deb"
        "$C/nvidia-legacy-340xx-smi_340.108-26_amd64.deb"
        "$C/xserver-xorg-video-nvidia-legacy-340xx_340.108-26_amd64.deb"
        "$C/nvidia-legacy-340xx-vdpau-driver_340.108-26_amd64.deb"
        "$C/nvidia-legacy-340xx-driver_340.108-26_amd64.deb"
        "$C/nvidia340_3_all.deb"
    )
    local MISS=() p
    for p in "${PKGS[@]}"; do
        [[ -f "$p" ]] || MISS+=("$p")
    done
    if [[ ${#MISS[@]} -gt 0 ]]; then
        error "Brak plików w cache apt:"
        printf '  %s\n' "${MISS[@]}" >&2
        exit 1
    fi

    apt-get install -y "${PKGS[@]}"

    if ! ( set +o pipefail; dkms status 2>/dev/null | grep -q "nvidia-legacy-340xx.*${KERN}.*installed" ); then
        info "dkms install dla $KERN..."
        if ! dkms install nvidia-legacy-340xx/340.108 -k "$KERN"; then
            tail -60 /var/lib/dkms/nvidia-legacy-340xx/340.108/build/make.log 2>/dev/null || true
            fix_dkms_via_prebuild || true
            dkms install nvidia-legacy-340xx/340.108 -k "$KERN" || exit 1
        fi
    fi

    TARGET_KERNEL="$KERN" cmd_restore_config
}

cmd_monitor_launchpad() {
    local CHECK_URL="${CHECK_URL:-https://ppa.launchpadcontent.net/kda2210/nvidia340/ubuntu/dists/noble/InRelease}"
    local INTERVAL_SEC="${INTERVAL_SEC:-300}"
    local RUN_COMPLETION="${RUN_COMPLETION:-1}"
    local LOG_DIR="${LOG_DIR:-$HOME/.local/share/nvidia340-launchpad-monitor}"
    local LOG_FILE="${LOG_DIR}/monitor.log"
    local READY_FLAG="${LOG_DIR}/launchpad-ppa-ready.flag"
    local SUDO_REFRESH="${SUDO_REFRESH:-0}"

    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

    mkdir -p "$LOG_DIR"
    trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

    log() { echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"; }

    check_launchpad() {
        curl -4 -fSs --connect-timeout 15 --max-time 35 -o /dev/null "$CHECK_URL" 2>/dev/null
    }

    notify_ok() {
        local msg="Launchpad OK. Uruchom: sudo bash ${SELF_ABS} --complete-online"
        command -v notify-send >/dev/null 2>&1 && DISPLAY="${DISPLAY:-:0}" notify-send -a "nvidia340-monitor" "Launchpad dostępny" "$msg" 2>/dev/null || true
    }

    run_completion() {
        if sudo -n true 2>/dev/null; then
            log "[INFO] sudo NOPASSWD — uruchamiam --complete-online"
            sudo bash "$SELF_ABS" --complete-online >>"$LOG_FILE" 2>&1 || log "[ERROR] --complete-online zakończył się błędem"
        else
            log "[INFO] Podaj hasło: sudo bash ${SELF_ABS} --complete-online"
            notify_ok
        fi
    }

    sudo_refresh_loop() {
        [[ "$SUDO_REFRESH" == "1" ]] || return 0
        while true; do sleep 2700; sudo -v 2>/dev/null || true; done
    }

    log "[INFO] Monitor START URL=$CHECK_URL co ${INTERVAL_SEC}s"
    [[ "$SUDO_REFRESH" == "1" ]] && sudo -v 2>/dev/null && sudo_refresh_loop &

    while true; do
        if check_launchpad; then
            log "[SUCCESS] Launchpad odpowiada."
            date -Is >"$READY_FLAG"
            echo "CHECK_URL=$CHECK_URL" >>"$READY_FLAG"
            notify_ok
            [[ "$RUN_COMPLETION" == "1" ]] && run_completion
            log "[INFO] Koniec monitora. Flaga: $READY_FLAG"
            exit 0
        fi
        log "[CHECK] Ponownie za ${INTERVAL_SEC}s"
        sleep "$INTERVAL_SEC"
    done
}

# Główna funkcja instalacji
main() {
    parse_leading_flags "$@"
    set -- "${PARSED_CMDLINE[@]}"
    apply_vaio_profile
    validate_target_kernel "$TARGET_KERNEL"

    if [[ "${DRY_RUN:-0}" == "1" && $# -eq 0 ]]; then
        info "[DRY-RUN] Brak podkomendy — pomijam tryb interaktywny. Przykład: sudo bash $0 --dry-run --post-install"
        exit 0
    fi

    case "${1:-}" in
        --fix-dkms)
            require_sudo_or_dry_run
            fix_dkms_via_prebuild || exit 1
            success "Naprawa DKMS zakończona. Zrestartuj system."
            exit 0
            ;;
        --post-install)
            require_sudo_or_dry_run
            configure_grub
            create_x11_config
            configure_gsk_renderer
            success "Konfiguracja GRUB / X11 / GSK zakończona. Zrestartuj system (GDM: Xorg)."
            exit 0
            ;;
        --complete-online)
            cmd_complete_online
            exit 0
            ;;
        --restore-config|--only-config)
            cmd_restore_config
            exit 0
            ;;
        --restore-full)
            cmd_restore_full
            exit 0
            ;;
        --install-local-cache)
            shift
            cmd_install_local_cache "$@"
            exit 0
            ;;
        --monitor-launchpad)
            shift
            cmd_monitor_launchpad "$@"
            exit 0
            ;;
        "")
            ;;
        *)
            error "Nieznana opcja: $1 — uruchom z --help"
            exit 1
            ;;
    esac

    echo "=========================================="
    echo "Instalacja sterowników NVIDIA 340 (nvidia340-ubuntu-2404)"
    echo "Ubuntu 24.04 — profil: acpi_backlight=${ACPI_BACKLIGHT}, LVDS 1366×768: $([[ "${LVDS_1366:-0}" == "1" ]] && echo tak || echo nie)"
    echo "=========================================="
    echo
    
    # Sprawdzenia wstępne
    check_sudo
    check_ubuntu_version
    check_nvidia_card
    
    echo
    warning "Ten skrypt wykona następujące operacje:"
    echo "  1. Dodanie PPA kda2210/nvidia340"
    echo "  2. Instalacja sterownika nvidia340"
    echo "  3. Konfiguracja GRUB (usunięcie nomodeset; acpi_backlight: ${ACPI_BACKLIGHT})"
    echo "  4. Utworzenie konfiguracji X11 (sekcja Monitor LVDS: $([[ "${LVDS_1366:-0}" == "1" ]] && echo tak || echo nie))"
    echo "  5. Konfiguracja GSK_RENDERER=cairo + override Ustawień (LIBGL_ALWAYS_SOFTWARE)"
    echo "  6. Opcjonalna weryfikacja instalacji"
    echo
    read -p "Kontynuować instalację? (t/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Tt]$ ]]; then
        info "Instalacja anulowana"
        exit 0
    fi
    
    # Krok 1: Dodanie PPA
    echo
    info "Krok 1/5: Dodawanie PPA kda2210/nvidia340..."
    if grep -q "kda2210/nvidia340" /etc/apt/sources.list.d/*.list 2>/dev/null || \
       grep -q "kda2210/nvidia340" /etc/apt/sources.list 2>/dev/null; then
        info "PPA kda2210/nvidia340 już istnieje, pomijam dodawanie"
    else
        add-apt-repository -y ppa:kda2210/nvidia340
    fi
    apt update
    success "PPA zostało dodane i zaktualizowane"
    
    # Krok 2: Instalacja sterownika
    echo
    info "Krok 2/5: Instalacja sterownika nvidia340..."
    info "To może zająć kilka minut..."
    set +e
    apt install -y nvidia340
    apt_ret=$?
    set -e
    if [ $apt_ret -ne 0 ]; then
        if [ -f /var/lib/dkms/nvidia-legacy-340xx/340.108/build/make.log ] && \
           grep -q "stdarg.h.*fatal error\|stdarg.h:.*No such file" /var/lib/dkms/nvidia-legacy-340xx/340.108/build/make.log 2>/dev/null; then
            warning "Błąd budowy DKMS (stdarg.h na jądrach 6.x). Stosuję poprawkę PRE_BUILD..."
            fix_dkms_via_prebuild || true
        fi
        if ! dpkg -s nvidia340 2>/dev/null | grep -q "Status: install ok installed"; then
            error "Błąd podczas instalacji sterownika nvidia340"
            error "Sprawdź logi: tail -100 /var/lib/dkms/nvidia-legacy-340xx/340.108/build/make.log"
            error "Ręczna naprawa: sudo $0 --fix-dkms"
            exit 1
        fi
    fi
    success "Sterownik nvidia340 został zainstalowany"
    
    # Krok 3: Konfiguracja GRUB
    echo
    info "Krok 3/5: Konfiguracja GRUB..."
    configure_grub
    
    # Krok 4: Konfiguracja X11
    echo
    info "Krok 4/5: Konfiguracja X11..."
    create_x11_config
    
    # Krok 5: Konfiguracja GSK_RENDERER dla aplikacji GNOME
    echo
    info "Krok 5/5: Konfiguracja GSK_RENDERER dla aplikacji GNOME..."
    configure_gsk_renderer
    
    # Weryfikacja
    echo
    read -p "Wykonać weryfikację instalacji? (t/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Tt]$ ]]; then
        verify_installation
    fi
    
    # Podsumowanie
    echo
    echo "=========================================="
    success "Instalacja zakończona!"
    echo "=========================================="
    echo
    warning "WAŻNE: Wymagany jest restart systemu, aby zmiany zaczęły działać."
    echo
    read -p "Uruchomić restart teraz? (t/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Tt]$ ]]; then
        info "Restartowanie systemu za 5 sekund..."
        sleep 5
        reboot
    else
        info "Zrestartuj system ręcznie: sudo reboot"
    fi
}

# Uruchom główną funkcję
main "$@"

