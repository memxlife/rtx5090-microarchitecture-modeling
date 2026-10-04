"""Measured response-window approximation, with strict experimental boundaries.

This is not an individual instruction latency or a complete GEMM timing model.
Selected four-load mixed cache outcomes are independently validated.
Cross-block contention and requests waiting on a shared outstanding fetch remain unvalidated.
"""
from dataclasses import dataclass
import json
from pathlib import Path

@dataclass(frozen=True)
class ProbeResponseCalibration:
    cold_base_cycles: float
    cold_extra_request_cycles: float
    cached_base_cycles: float
    cached_extra_request_cycles: float

    @classmethod
    def measured(cls):
        d=json.loads(Path(__file__).with_name('global_response_parameters.json').read_text())
        return cls(**{k:d[k] for k in cls.__dataclass_fields__})

    def window_cycles(self, group: int, cache_outcomes: list[str], warps: int = 4,
                      warp_stride_elements: int = 64) -> float:
        # Spacing is part of the measured domain, not an invisible assumption.
        # The original calibration uses64 BF16 elements between warp bases.
        if warp_stride_elements!=64:
            evidence=json.loads(Path(__file__).with_name('global_layout_evidence.json').read_text())
            if not (evidence['accepted'] and group==4 and warps==4
                    and cache_outcomes==['L2']*4
                    and warp_stride_elements in evidence['warm_group4_warps4_strides']):
                raise ValueError('Unvalidated request layout/cache combination.')
        # Groups1/4 development atW4; group2 independently confirmedW1/4/8.
        if not (warps==4 and group in [1,2,4] or group==2 and warps in [1,4,8]):
            raise ValueError('Unvalidated group or warp count.')
        if len(cache_outcomes)!=group or not all(x in ['L2','external'] for x in cache_outcomes):
            raise ValueError('Supply one validated cache outcome per request.')
        if len(set(cache_outcomes))!=1:
            supported=[['external','L2','L2','L2'],['L2','L2','L2','external'],
                       ['L2','external','external','external'],['L2','L2','external','external']]
            if group!=4 or warps!=4 or cache_outcomes not in supported:
                raise ValueError('Unvalidated mixed group, request ordering or warp count.')
            # One or more missing values retain the cold response base. The
            # increment is independently measured; no mixed timing fitted it.
            external=cache_outcomes.count('external')
            cached=group-external
            return (self.cold_base_cycles+(external-1)*self.cold_extra_request_cycles
                    +cached*self.cached_extra_request_cycles)
        if cache_outcomes[0]=='L2':
            return self.cached_base_cycles+(group-1)*self.cached_extra_request_cycles
        return self.cold_base_cycles+(group-1)*self.cold_extra_request_cycles

    def warm_first_row_group_cycles(self, layout: str, context_k: int,
                                    context_n: int = 96) -> float:
        evidence=json.loads(Path(__file__).with_name('actual_row_evidence.json').read_text())
        if not (evidence['accepted'] and layout in evidence['layouts']
                and context_k in evidence['context_k']
                and context_n==evidence['context_n']):
            raise ValueError('Unvalidated real-row response context.')
        # Existing parameters predict these independent layout tests within5%.
        # This admits the domain, not a new fitted cost or whole-stage transfer.
        return self.window_cycles(4,['L2']*4,4)
