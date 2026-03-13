#!/usr/bin/env bash
# Portable Linux bootstrap for ComfyUI + SageAttention v2++.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DEFAULT_BOOTSTRAP_CACHE_ROOT="$SCRIPT_DIR/.bootstrap-cache"
DEFAULT_BOOTSTRAP_CACHE_DIR="$DEFAULT_BOOTSTRAP_CACHE_ROOT/pacman-cache"
BOOTSTRAP_CACHE_DIR="${BOOTSTRAP_CACHE_DIR:-$DEFAULT_BOOTSTRAP_CACHE_DIR}"
COMFYUI_REPO_URL="${COMFYUI_REPO_URL:-https://github.com/comfyanonymous/ComfyUI.git}"
COMFYUI_DIR="${COMFYUI_DIR:-$SCRIPT_DIR/ComfyUI}"
COMFYUI_REF="${COMFYUI_REF:-}"
COMFYUI_SKIP_UPDATE="${COMFYUI_SKIP_UPDATE:-0}"
PYTHON311_FALLBACK_URL="${PYTHON311_FALLBACK_URL:-https://mirror.cachyos.org/repo/x86_64/cachyos/python311-3.11.14-1-x86_64.pkg.tar.zst}"
GCC14_FALLBACK_URL="${GCC14_FALLBACK_URL:-https://mirror.cachyos.org/repo/x86_64/cachyos/gcc14-14.3.1+r516+g5998566829ee-1-x86_64.pkg.tar.zst}"
GCC14_LIBS_FALLBACK_URL="${GCC14_LIBS_FALLBACK_URL:-https://mirror.cachyos.org/repo/x86_64/cachyos/gcc14-libs-14.3.1+r516+g5998566829ee-1-x86_64.pkg.tar.zst}"
CUDA131_URL="${CUDA131_URL:-https://archive.archlinux.org/packages/c/cuda/cuda-13.1.1-1-x86_64.pkg.tar.zst}"
SAGEATTENTION_TARGET_VERSION="${SAGEATTENTION_TARGET_VERSION:-2.2.0}"
SAGEATTENTION_FALLBACK_VERSION="${SAGEATTENTION_FALLBACK_VERSION:-1.0.6}"

require_linux_x86_64() {
    if [ "$(uname -s)" != "Linux" ]; then
        echo "ERROR: comfy-sage is Linux-only." >&2
        exit 1
    fi

    if [ "$(uname -m)" != "x86_64" ]; then
        echo "ERROR: comfy-sage currently supports only Linux x86_64." >&2
        exit 1
    fi
}

require_bootstrap_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command '$1' is not installed." >&2
        exit 1
    fi
}

has_bsdtar() {
    command -v bsdtar >/dev/null 2>&1
}

has_gnu_tar_zstd() {
    command -v tar >/dev/null 2>&1 && tar --help 2>&1 | grep -q -- "--zstd"
}

require_archive_tool() {
    if has_bsdtar || has_gnu_tar_zstd; then
        return 0
    fi

    echo "ERROR: install bsdtar, or GNU tar with --zstd support." >&2
    exit 1
}

archive_is_valid() {
    local archive="$1"

    [ -f "$archive" ] || return 1

    if has_bsdtar; then
        bsdtar -tf "$archive" >/dev/null 2>&1
    else
        tar --zstd -tf "$archive" >/dev/null 2>&1
    fi
}

extract_archive() {
    local archive="$1"
    local target="$2"
    shift 2

    mkdir -p "$target"

    if has_bsdtar; then
        bsdtar -xf "$archive" -C "$target" "$@"
    else
        tar --zstd -xf "$archive" -C "$target" "$@"
    fi
}

download_archive() {
    local url="$1"
    local archive="$2"
    local partial="${archive}.part"
    local attempt

    mkdir -p "$(dirname "$archive")"

    if archive_is_valid "$archive"; then
        return 0
    fi

    rm -f "$archive"

    for attempt in 1 2; do
        echo "Downloading $(basename "$archive")..."
        curl -L --fail -C - --output "$partial" "$url"

        if archive_is_valid "$partial"; then
            mv "$partial" "$archive"
            return 0
        fi

        echo "warning: invalid archive downloaded from $url (attempt $attempt)" >&2
        rm -f "$partial"
    done

    echo "ERROR: failed to download a valid archive from $url" >&2
    return 1
}

prepare_bootstrap_cache_dir() {
    local cache_subdir

    if [ "$BOOTSTRAP_CACHE_DIR" = "$DEFAULT_BOOTSTRAP_CACHE_DIR" ]; then
        mkdir -p "$DEFAULT_BOOTSTRAP_CACHE_ROOT"
        cache_subdir="$(basename "$DEFAULT_BOOTSTRAP_CACHE_DIR")"
        if [ ! -e "$DEFAULT_BOOTSTRAP_CACHE_DIR" ]; then
            mkdir -p "$DEFAULT_BOOTSTRAP_CACHE_DIR"
            find "$DEFAULT_BOOTSTRAP_CACHE_ROOT" -mindepth 1 -maxdepth 1 -type f ! -name "$cache_subdir" -exec mv -n {} "$DEFAULT_BOOTSTRAP_CACHE_DIR"/ \;
        fi
    fi

    mkdir -p "$BOOTSTRAP_CACHE_DIR"
}

resolve_cachyos_url() {
    local package="$1"
    local fallback_url="$2"
    local url=""

    if command -v pacman >/dev/null 2>&1; then
        url=$(pacman -Sp "$package" 2>/dev/null | grep -E "/${package}-[0-9]" | head -n 1 || true)
        if [ -n "$url" ]; then
            url="${url/https:\/\/cdn77.cachyos.org\/repo\/x86_64\/cachyos\//https:\/\/mirror.cachyos.org\/repo\/x86_64\/cachyos\/}"
        fi
    fi

    printf '%s\n' "${url:-$fallback_url}"
}

ensure_local_python311() {
    local target="$SCRIPT_DIR/local-python311"
    local archive
    local url

    if [ -x "$target/usr/bin/python3.11" ] && [ -f "$target/usr/lib/libpython3.11.so.1.0" ]; then
        return 0
    fi

    url=$(resolve_cachyos_url "python311" "$PYTHON311_FALLBACK_URL")
    archive="$BOOTSTRAP_CACHE_DIR/$(basename "${url%%\?*}")"
    download_archive "$url" "$archive"
    extract_archive "$archive" "$target" usr

    if [ ! -x "$target/usr/bin/python3.11" ]; then
        echo "ERROR: local python3.11 bootstrap failed." >&2
        exit 1
    fi
}

ensure_local_gcc14() {
    local target="$SCRIPT_DIR/local-gcc14"
    local main_url
    local libs_url
    local main_archive
    local libs_archive

    if [ -x "$target/usr/bin/gcc-14" ] && [ -x "$target/usr/bin/g++-14" ] && [ -f "$target/usr/lib/gcc/x86_64-pc-linux-gnu/14.3.1/libstdc++.so" ]; then
        return 0
    fi

    main_url=$(resolve_cachyos_url "gcc14" "$GCC14_FALLBACK_URL")
    libs_url=$(resolve_cachyos_url "gcc14-libs" "$GCC14_LIBS_FALLBACK_URL")
    main_archive="$BOOTSTRAP_CACHE_DIR/$(basename "${main_url%%\?*}")"
    libs_archive="$BOOTSTRAP_CACHE_DIR/$(basename "${libs_url%%\?*}")"

    download_archive "$main_url" "$main_archive"
    download_archive "$libs_url" "$libs_archive"

    extract_archive "$main_archive" "$target" usr
    extract_archive "$libs_archive" "$target" usr

    if [ ! -x "$target/usr/bin/gcc-14" ] || [ ! -x "$target/usr/bin/g++-14" ]; then
        echo "ERROR: local gcc14 bootstrap failed." >&2
        exit 1
    fi
}

ensure_local_cuda131() {
    local target="$SCRIPT_DIR/local-cuda131"
    local archive

    archive="$BOOTSTRAP_CACHE_DIR/$(basename "${CUDA131_URL%%\?*}")"

    if [ -x "$target/opt/cuda/bin/nvcc" ]; then
        return 0
    fi

    download_archive "$CUDA131_URL" "$archive"
    extract_archive "$archive" "$target" opt/cuda

    if [ ! -x "$target/opt/cuda/bin/nvcc" ]; then
        echo "ERROR: local CUDA 13.1 bootstrap failed." >&2
        exit 1
    fi
}

bootstrap_local_toolchain() {
    require_linux_x86_64
    require_bootstrap_command curl
    require_bootstrap_command git
    require_archive_tool
    prepare_bootstrap_cache_dir
    ensure_local_python311
    ensure_local_gcc14
    ensure_local_cuda131
}

bootstrap_local_toolchain

PYTHON_BIN=python3
VENV_DIR=comfyenv

if [ -x "$SCRIPT_DIR/local-python311/usr/bin/python3.11" ]; then
    PYTHON_BIN="$SCRIPT_DIR/local-python311/usr/bin/python3.11"
    VENV_DIR=comfyenv311
    export LD_LIBRARY_PATH="$SCRIPT_DIR/local-python311/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
elif command -v python3.13 >/dev/null 2>&1; then
    PYTHON_BIN=python3.13
elif [ -x "$SCRIPT_DIR/python3.13/bin/python3.13" ]; then
    PYTHON_BIN="$SCRIPT_DIR/python3.13/bin/python3.13"
fi

if [[ "$PYTHON_BIN" = *"3.11"* ]]; then
    echo "Using $PYTHON_BIN for the virtual environment (preferred for SageAttention v2++ builds)"
elif [[ "$PYTHON_BIN" = *"3.13"* ]]; then
    echo "Using $PYTHON_BIN for the virtual environment"
else
    echo "warning: neither local python3.11 nor python3.13 was found; using default python3 ($PYTHON_BIN)."
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python venv in ./$VENV_DIR..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip setuptools wheel ninja

setup_local_cuda_home() {
    local candidate=""

    if [ -n "${CUDA_HOME:-}" ] && [ -x "${CUDA_HOME}/bin/nvcc" ]; then
        candidate="$CUDA_HOME"
    elif [ -x "$SCRIPT_DIR/local-cuda131/opt/cuda/bin/nvcc" ]; then
        candidate="$SCRIPT_DIR/local-cuda131/opt/cuda"
    elif [ -x "$SCRIPT_DIR/local-cuda/opt/cuda/bin/nvcc" ]; then
        candidate="$SCRIPT_DIR/local-cuda/opt/cuda"
    elif [ -x "$SCRIPT_DIR/local-cuda/bin/nvcc" ]; then
        candidate="$SCRIPT_DIR/local-cuda"
    fi

    if [ -n "$candidate" ]; then
        export CUDA_HOME="$candidate"
        export CUDA_PATH="$candidate"
        export PATH="$candidate/bin:$PATH"
        if [ -d "$candidate/lib64" ]; then
            export LD_LIBRARY_PATH="$candidate/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi
        if [ "$candidate" = "$SCRIPT_DIR/local-cuda131/opt/cuda" ]; then
            export TORCH_ALLOW_CUDA_MAJOR_MISMATCH=1
        fi
        echo "Using CUDA toolkit from $candidate"
    fi
}

setup_local_cuda_home

setup_local_gcc_toolchain() {
    local prefix="$SCRIPT_DIR/local-gcc14/usr"
    local gcc_lib="$prefix/lib/gcc/x86_64-pc-linux-gnu/14.3.1"

    if [ -x "$prefix/bin/gcc-14" ] && [ -x "$prefix/bin/g++-14" ]; then
        export PATH="$prefix/bin:$PATH"
        export LD_LIBRARY_PATH="$gcc_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        export CC="$prefix/bin/gcc-14"
        export CXX="$prefix/bin/g++-14"
        export CUDAHOSTCXX="$prefix/bin/g++-14"
        echo "Using GCC toolchain from $prefix/bin"
    fi
}

setup_local_gcc_toolchain

pyver=$(python -c 'import sys;print("%d.%d"%sys.version_info[:2])')

version_ge() {
    python - "$1" "$2" <<'PYTHON'
import re
import sys

def parse(version: str):
    version = re.split(r"[+-]", version, maxsplit=1)[0]
    return tuple(int(part) for part in version.split("."))

sys.exit(0 if parse(sys.argv[1]) >= parse(sys.argv[2]) else 1)
PYTHON
}

install_torch() {
    echo "Attempting to install PyTorch (CUDA enabled) for Python $pyver..."
    python -m pip install --upgrade torch torchvision torchaudio || return 1
}

check_cuda_build() {
    python - <<'PYTHON'
import sys

try:
    import torch
    v = torch.version.cuda or "cpu"
    if v == "cpu":
        print("WARNING: installed PyTorch is CPU-only")
    else:
        major, minor = (int(part) for part in v.split(".")[:2])
        if (major, minor) < (12, 8):
            print(
                f"WARNING: SageAttention 2.2.0 (v2++) needs PyTorch built against "
                f"CUDA 12.8 or newer; currently installed cuda{v}."
            )
            print("Consider using a newer CUDA-enabled PyTorch build.")
except ImportError:
    print("WARNING: PyTorch not installed.")
    sys.exit(1)
PYTHON
}

torch_cuda_version() {
    python - <<'PYTHON'
import sys

try:
    import torch
    print(torch.version.cuda or "")
except Exception:
    sys.exit(1)
PYTHON
}

get_sage_version() {
    python - <<'PYTHON'
import sys
from importlib.metadata import PackageNotFoundError, version

try:
    print(version("sageattention"))
except PackageNotFoundError:
    sys.exit(1)
PYTHON
}

patch_torch_cpp_extension() {
    python - <<'PYTHON'
from pathlib import Path
import importlib.util
import sys

spec = importlib.util.find_spec("torch.utils.cpp_extension")
if spec is None or spec.origin is None:
    sys.exit(0)

path = Path(spec.origin)
text = path.read_text()
needle = "os.environ.get('TORCH_ALLOW_CUDA_MAJOR_MISMATCH')"
if needle in text:
    sys.exit(0)

old = """        if cuda_ver.major != torch_cuda_version.major:\n            raise RuntimeError(CUDA_MISMATCH_MESSAGE, cuda_str_version, torch.version.cuda)\n        logger.warning(CUDA_MISMATCH_WARN, cuda_str_version, torch.version.cuda)\n"""
new = """        if cuda_ver.major != torch_cuda_version.major:\n            if os.environ.get('TORCH_ALLOW_CUDA_MAJOR_MISMATCH') in ['ON', '1', 'YES', 'TRUE', 'Y']:\n                logger.warning(CUDA_MISMATCH_WARN, cuda_str_version, torch.version.cuda)\n            else:\n                raise RuntimeError(CUDA_MISMATCH_MESSAGE, cuda_str_version, torch.version.cuda)\n        logger.warning(CUDA_MISMATCH_WARN, cuda_str_version, torch.version.cuda)\n"""

if old not in text:
    print("warning: torch cpp_extension mismatch block not found; skipping local patch")
    sys.exit(0)

path.write_text(text.replace(old, new))
print(f"patched {path} to allow TORCH_ALLOW_CUDA_MAJOR_MISMATCH")
PYTHON
}

get_nvidia_gpu_name() {
    local name=""

    if command -v nvidia-smi >/dev/null 2>&1; then
        name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 || true)
    fi

    if [ -z "$name" ]; then
        name=$(sed -n 's/^Model:[[:space:]]*//p' /proc/driver/nvidia/gpus/*/information 2>/dev/null | head -n 1 || true)
    fi

    if [ -z "$name" ] && command -v lspci >/dev/null 2>&1; then
        name=$(lspci -nn | grep -iE 'VGA|3D' | grep -i 'NVIDIA' | head -n 1 | sed 's/^.*NVIDIA Corporation //')
    fi

    [ -n "$name" ] && printf '%s\n' "$name"
}

gpu_is_blackwell() {
    case "${1^^}" in
        *"BLACKWELL"*|*" RTX 50"*|*"RTX PRO 6000"*|*" B100"*|*" B200"*|*"GB200"*)
            return 0
            ;;
    esac
    return 1
}

has_torch_cuda_build() {
    python - <<'PYTHON'
import sys

try:
    import torch
except Exception:
    sys.exit(1)
sys.exit(0 if torch.version.cuda else 1)
PYTHON
}

has_torch_gpu() {
    python - <<'PYTHON'
import sys

try:
    import torch
except Exception:
    sys.exit(1)
sys.exit(0 if torch.cuda.is_available() else 1)
PYTHON
}

should_enable_sage_attention() {
    if ! has_torch_gpu; then
        return 1
    fi

    python - <<'PYTHON'
import importlib.util
import sys

sys.exit(0 if importlib.util.find_spec("sageattention") else 1)
PYTHON
}

install_sage() {
    echo "Installing/upgrading SageAttention support..."

    local current_version=""
    local gpu_name=""
    local torch_cuda=""

    current_version=$(get_sage_version 2>/dev/null || true)
    gpu_name=$(get_nvidia_gpu_name || true)
    torch_cuda=$(torch_cuda_version || true)

    if [ -n "$current_version" ]; then
        echo "Detected sageattention version $current_version"
    fi

    if [ -n "$gpu_name" ]; then
        echo "Detected NVIDIA GPU: $gpu_name"
        if gpu_is_blackwell "$gpu_name"; then
            echo "Blackwell GPU detected; comfy-sage still targets the ComfyUI --use-sage-attention path."
        fi
    fi

    if [ -n "$torch_cuda" ]; then
        echo "Detected PyTorch CUDA build: $torch_cuda"
    fi

    if [ -n "$current_version" ] && version_ge "$current_version" "$SAGEATTENTION_TARGET_VERSION"; then
        echo "Keeping installed sageattention $current_version"
        return 0
    fi

    if [ -n "$gpu_name" ] && [ -n "$torch_cuda" ] && version_ge "$torch_cuda" "12.8"; then
        if command -v nvcc >/dev/null 2>&1; then
            echo "Trying SageAttention ${SAGEATTENTION_TARGET_VERSION}..."
            if python -m pip install --upgrade --no-build-isolation "sageattention==${SAGEATTENTION_TARGET_VERSION}"; then
                current_version=$(get_sage_version 2>/dev/null || true)
                echo "Installed sageattention version ${current_version:-unknown}"
                return 0
            fi

            echo "warning: exact SageAttention install failed; trying the upstream repository."
            if python -m pip install --upgrade --no-build-isolation "git+https://github.com/thu-ml/SageAttention.git@main"; then
                current_version=$(get_sage_version 2>/dev/null || true)
                echo "Installed sageattention version ${current_version:-unknown}"
                return 0
            fi

            echo "warning: SageAttention v2++ install failed; falling back to the compatibility path."
        else
            echo "nvcc not found; SageAttention v2++ needs a CUDA toolkit with nvcc available."
        fi
    fi

    if [ -n "$current_version" ]; then
        echo "Keeping installed sageattention $current_version"
        return 0
    fi

    echo "Falling back to SageAttention ${SAGEATTENTION_FALLBACK_VERSION}."
    if python -m pip install --upgrade "sageattention==${SAGEATTENTION_FALLBACK_VERSION}"; then
        current_version=$(get_sage_version 2>/dev/null || true)
        echo "Installed sageattention version ${current_version:-unknown}"
    else
        echo "warning: could not install sageattention; ComfyUI may fail with --use-sage-attention"
    fi
}

if ! has_torch_cuda_build; then
    if install_torch; then
        check_cuda_build
    else
        echo "WARNING: PyTorch GPU install failed for Python $pyver." >&2
        echo "You can still run ComfyUI on CPU, but SageAttention v2++ will not be available." >&2
    fi
fi

if python -c 'import importlib, sys
try:
    importlib.import_module("torch")
    sys.exit(0)
except ImportError:
    sys.exit(1)'; then
    patch_torch_cpp_extension
fi

if has_torch_cuda_build && ! has_torch_gpu; then
    echo "WARNING: PyTorch has a CUDA build, but this shell cannot access the NVIDIA GPU right now."
    echo "SageAttention can still be installed, but ComfyUI will not benefit until torch.cuda.is_available() works."
fi

if python -c 'import importlib, sys
try:
    importlib.import_module("torch")
    sys.exit(0)
except ImportError:
    sys.exit(1)'; then
    install_sage
else
    echo "skipping SageAttention installation because torch is missing"
fi

clone_or_update_comfyui() {
    if [ -d "$COMFYUI_DIR/.git" ]; then
        echo "Using existing ComfyUI checkout at $COMFYUI_DIR"
        cd "$COMFYUI_DIR"
        if [ "$COMFYUI_SKIP_UPDATE" = "1" ]; then
            echo "Skipping ComfyUI update because COMFYUI_SKIP_UPDATE=1"
        elif [ -n "$COMFYUI_REF" ]; then
            git fetch origin "$COMFYUI_REF" --depth 1 || true
            git checkout FETCH_HEAD || true
        else
            git pull --ff-only || true
        fi
        return 0
    fi

    if [ -e "$COMFYUI_DIR" ]; then
        echo "ERROR: $COMFYUI_DIR exists but is not a git checkout." >&2
        exit 1
    fi

    echo "Cloning ComfyUI repository..."
    if [ -n "$COMFYUI_REF" ]; then
        git clone --depth 1 --branch "$COMFYUI_REF" "$COMFYUI_REPO_URL" "$COMFYUI_DIR"
    else
        git clone --depth 1 "$COMFYUI_REPO_URL" "$COMFYUI_DIR"
    fi
}

clone_or_update_comfyui
cd "$COMFYUI_DIR"

python -m pip install -r requirements.txt

clean_args=()
has_attention_flag=0
for arg in "$@"; do
    case "$arg" in
        --fast)
            echo "warning: --fast is known to produce black images and will be ignored"
            ;;
        --use-split-cross-attention|--use-quad-cross-attention|--use-pytorch-cross-attention|--use-sage-attention|--use-flash-attention)
            has_attention_flag=1
            clean_args+=("$arg")
            ;;
        *)
            clean_args+=("$arg")
            ;;
    esac
done

if [ "$has_attention_flag" -eq 0 ]; then
    if should_enable_sage_attention; then
        echo "enabling --use-sage-attention (CUDA + sageattention detected)"
        clean_args+=("--use-sage-attention")
    else
        echo "not enabling --use-sage-attention by default because CUDA or sageattention is not ready"
    fi
fi

echo "Launching ComfyUI..."
python main.py "${clean_args[@]}"
