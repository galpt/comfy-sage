# Third-Party Notices

`comfy-sage` ships bootstrap scripts and release automation. It does not bundle
ComfyUI, SageAttention, PyTorch, CUDA, or NVIDIA drivers in this repository.
Those components are downloaded or installed at runtime by `launch-comfy.sh`
and remain subject to their own licenses and distribution terms.

## Components fetched at runtime

- ComfyUI
  - Upstream: <https://github.com/comfyanonymous/ComfyUI>
  - License: GPL-3.0-or-later
  - Notes: cloned into `./ComfyUI` on first launch. The cloned checkout
    includes its own `LICENSE` file.

- SageAttention
  - Upstream: <https://github.com/thu-ml/SageAttention>
  - License: Apache-2.0
  - Notes: installed into the local virtual environment. Installed package
    metadata includes the upstream license.

- PyTorch, torchvision, torchaudio, Triton, and Python dependencies required by
  ComfyUI or SageAttention
  - Upstream: respective project repositories and package indexes
  - License: project specific
  - Notes: installed into the local virtual environment at first launch.

- CUDA toolkit bootstrap archive
  - Source: Arch Linux package archive
  - License: NVIDIA CUDA EULA and bundled third-party licenses
  - Notes: extracted into `./local-cuda131`.

- Python 3.11 and GCC 14 bootstrap archives
  - Source: CachyOS package repository
  - License: package specific
  - Notes: extracted into `./local-python311` and `./local-gcc14`.

## Repository license boundary

The files committed in this repository are licensed under the MIT license in
[`LICENSE`](LICENSE). That license does not replace or override the licenses of
software fetched at runtime.
