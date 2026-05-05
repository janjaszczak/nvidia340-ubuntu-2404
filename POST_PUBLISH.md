# After publishing on GitHub (checklist)

Do these in the GitHub **web UI** for the public repository:

1. **Settings → Code security and analysis**
   - Enable **Private vulnerability reporting** (recommended).
   - Enable **Dependabot alerts** (low noise today; useful if you add manifests later).

2. **About** (repository header)
   - Add a short **Description** (English), e.g. *Helper script and docs for NVIDIA 340.108 on Ubuntu 24.04 (Xorg, DKMS 6.x).*  
   - **Topics / tags:** `nvidia`, `ubuntu`, `dkms`, `gnome`, `gtk4`, `xorg`, `nvidia-340`

3. **CI:** workflow `.github/workflows/shellcheck.yml` should run on `main` and PRs.

4. Optional: add **branch protection** on `main` (require PR + status checks).
