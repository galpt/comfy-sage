# comfy-sage

Portable Linux bootstrap for ComfyUI with SageAttention v2++.

This repository is for NVIDIA users who want a small release zip that they can
unpack and run locally. The first launch bootstraps a self-contained runtime in
the unpacked directory:

- local Python 3.11
- local GCC 14
- local CUDA 13.1 toolkit
- a local virtual environment
- ComfyUI
- PyTorch with CUDA
- SageAttention `2.2.0` (`v2++`)

After the first run, the directory stays self-contained. You can move it, keep
multiple copies, or delete it without affecting your system Python or system
CUDA installation.

## What this project is

`comfy-sage` is a Linux-only launcher and release pipeline. It does not try to
ship a giant prebuilt GPU image through GitHub Releases. Instead, release
assets contain the launcher plus documentation, and the launcher downloads the
required pieces into the local folder on first run.

That is the practical tradeoff:

- small GitHub release asset
- fully local runtime after bootstrap
- no global Python/CUDA setup required
- honest scope: Linux `x86_64` with an NVIDIA GPU

## Supported target

- OS: Linux `x86_64`
- GPU: NVIDIA
- Driver: working proprietary driver with CUDA available to PyTorch
- SageAttention mode: `v2++` (`sageattention==2.2.0`)

## Not supported

- macOS
- Windows
- AMD or Intel GPUs
- CPU-only SageAttention

If the machine does not satisfy the CUDA requirements, the launcher can still
fall back to a slower ComfyUI path, but this repository is specifically aimed
at the Linux + NVIDIA + SageAttention `v2++` case.

## Runtime prerequisites

The launcher expects these commands to exist on the host:

- `bash`
- `curl`
- `git`
- `bsdtar`, or `tar` with `--zstd` support

You also need a working NVIDIA driver already installed on the machine.

## Quick start

1. Download the latest `comfy-sage-linux-x86_64-vX.Y.Z.zip` from GitHub
   Releases.
2. Unzip it anywhere.
3. `cd` into the unpacked directory.
4. Run:

```bash
chmod +x launch-comfy.sh
./launch-comfy.sh
```

Any extra arguments are forwarded to `ComfyUI/main.py`:

```bash
./launch-comfy.sh --listen 0.0.0.0 --port 8188
```

If you do not explicitly set another attention backend, the launcher will add
`--use-sage-attention` automatically when CUDA and SageAttention are ready.

## What the launcher does

On first run it will:

1. bootstrap a local toolchain into the current directory
2. create `./comfyenv311`
3. install PyTorch, torchvision, torchaudio, and build tooling
4. install or upgrade SageAttention to `2.2.0`
5. clone ComfyUI into `./ComfyUI`
6. install ComfyUI requirements
7. launch ComfyUI

## Layout after first run

```text
comfy-sage/
├── ComfyUI/
├── comfyenv311/
├── local-cuda131/
├── local-gcc14/
├── local-python311/
├── .bootstrap-cache/
│   └── pacman-cache/
└── launch-comfy.sh
```

## Configuration knobs

Optional environment variables:

- `BOOTSTRAP_CACHE_DIR`: where bootstrap archives are cached
  Default: `./.bootstrap-cache/pacman-cache`
- `COMFYUI_DIR`: override the local ComfyUI checkout path
- `COMFYUI_REPO_URL`: override the ComfyUI git remote
- `COMFYUI_REF`: clone a specific branch or tag
- `COMFYUI_SKIP_UPDATE=1`: skip `git pull` on existing ComfyUI checkouts
- `SAGEATTENTION_TARGET_VERSION`: override the preferred SageAttention version

## Release workflow

This repository includes GitHub Actions workflows that:

- validate the launcher and packaging logic in CI
- build a Linux release zip
- generate a SHA-256 checksum
- create a Git tag and GitHub Release

Versioning is driven by the root [`VERSION`](VERSION) file.

## License

The bootstrap scripts and automation in this repository are MIT licensed. See
[`LICENSE`](LICENSE).

ComfyUI, SageAttention, PyTorch, CUDA, and other dependencies keep their own
licenses. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
