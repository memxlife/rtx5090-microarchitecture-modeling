"""Measured complete-path costs for model and MILP coefficient construction.

These costs replace the tested path. They must not be added to a decomposition
of the same issue, memory response, and dependent wakeup delays.
"""
import json
from pathlib import Path

PROFILE = Path(__file__).with_name("initial_validation_effective_profile.json")


def shared_scalar_dependency_cycles(byte_addresses, profile=None):
    """One full warp, scalar LDS: duplicate words share a bank service."""
    if len(byte_addresses) != 32 or any(a < 0 or a % 4 for a in byte_addresses):
        raise ValueError("Measured domain requires 32 nonnegative, word-aligned addresses")
    config = (profile or json.loads(PROFILE.read_text()))["shared_scalar_dependency"]
    banks = [set() for _ in range(config["bank_count"])]
    for address in byte_addresses:
        word = address // config["bank_word_bytes"]
        banks[word % len(banks)].add(word)
    packages = max(map(len, banks))
    return config["base_SM_cycles"] + config["additional_SM_cycles_per_distinct_bank_word"] * (packages - 1)


def dependent_cached_load_cycles(path, working_set_bytes=8192, profile=None):
    """Return the observed recurrence for the exact small resident chain."""
    if path not in {"L1_dependent_ca", "L2_dependent_cg"}:
        raise ValueError("Only the measured ca/cg chain paths are supported")
    config = (profile or json.loads(PROFILE.read_text()))[path]
    if working_set_bytes != config["working_set_bytes"]:
        raise ValueError("Other working sets require a cache-hit/miss model")
    return config["effective_SM_cycles"]


def compose_gemm_phases_us(common_us, staging_only_us, compute_only_us, interaction_fraction):
    """Provisional compiled-kernel interaction model, not an intrinsic overlap rule.

    Each isolated phase includes the common work. Remove that work once, then
    subtract a calibrated fraction of the smaller remaining phase cost. The
    coefficient is restricted to the tested tile and compiled kernel family.
    """
    if min(common_us, staging_only_us, compute_only_us) < 0:
        raise ValueError("Phase durations must be nonnegative")
    staging = staging_only_us - common_us
    compute = compute_only_us - common_us
    if min(staging, compute) < 0 or not 0 <= interaction_fraction <= 1:
        raise ValueError("Invalid common duration or interaction fraction")
    return common_us + staging + compute - interaction_fraction * min(staging, compute)
