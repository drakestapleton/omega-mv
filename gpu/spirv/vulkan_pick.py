# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Choose a Vulkan device for an unattended UXL run.

Intel GPUs and software devices (lavapipe, device type CPU) are eligible.
Any other hardware GPU is skipped unless the caller passed --gpu, or the
parent set UXL_GPU=1. A higher rank wins. Ties keep the first device.
"""

import os

INTEL = 0x8086
# VkPhysicalDeviceType
TYPE_OTHER = 0
TYPE_INTEGRATED = 1
TYPE_DISCRETE = 2
TYPE_VIRTUAL = 3
TYPE_CPU = 4


def allow_other_gpus(argv):
    if "--gpu" in argv:
        return True
    return os.environ.get("UXL_GPU") == "1"


def strip_gpu_flag(argv):
    return [arg for arg in argv if arg != "--gpu"]


def device_class(vendor, dtype):
    if dtype == TYPE_CPU:
        return "software"
    if vendor == INTEL and dtype in (TYPE_INTEGRATED, TYPE_DISCRETE, TYPE_VIRTUAL):
        return "intel"
    if dtype in (TYPE_INTEGRATED, TYPE_DISCRETE, TYPE_VIRTUAL, TYPE_OTHER):
        return "gpu"
    return "other"


def rank_device(vendor, dtype, allow_gpu):
    """Return a rank, or None when this device must not be opened."""
    kind = device_class(vendor, dtype)
    if kind == "intel":
        return 3
    if kind == "software":
        return 1
    if kind == "gpu" and allow_gpu:
        return 2
    return None
