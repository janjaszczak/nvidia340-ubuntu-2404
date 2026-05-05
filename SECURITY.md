# Security policy

## Supported versions

Best-effort maintenance for the `main` branch of **nvidia340-ubuntu-2404** (shell script + documentation). This is a hobbyist / community helper, not a commercial product.

## Reporting a vulnerability

- Prefer **GitHub Private vulnerability reporting** (Repository → Security → Advisories) if enabled.
- Otherwise open a **private** issue only if it does not expose exploit details publicly, or contact the maintainer via GitHub profile if available.

Please include: affected file, reproduction steps, impact, suggested fix (if any).

## Scope (in scope)

- `install-nvidia340.sh` (logic that could lead to privilege escalation, unsafe writes, command injection, weak handling of user input).
- Documentation that could mislead users into unsafe operations.

## Out of scope

- **NVIDIA proprietary driver 340.108** and its binaries, DKMS upstream sources, or NVIDIA EULA/security response — report to NVIDIA / use distro and legal channels as appropriate.
- **Ubuntu kernel** packages, **APT**, or **systemd** — report to Canonical / upstream.
- **Third-party PPA** `kda2210/nvidia340` (package contents, signing, availability) — not maintained in this repo; use Launchpad and PPA owner channels.
- Hardware-specific stability (LVDS, backlight, GPU silicon).

## Response times

Best-effort; no SLA. Critical issues (e.g. clear remote code execution from script usage) will be prioritized when noticed.
