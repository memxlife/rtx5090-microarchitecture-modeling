"""Bounded response-group readiness model for the independent RTX5090 probe.

A repeated lookup can refer to a fetch still in flight. State stores an
availability time, not just a boolean cache presence. Validated timing scope:
four full-warp requests, four warps, paired blocks issuing the same group
simultaneously or after its data has arrived (diagnostic021). Intermediate
arrival skews, partial pending groups and global contention remain unvalidated.
Caller must invalidate entries when its cache model evicts them.
"""
from dataclasses import dataclass, field
from .global_response import ProbeResponseCalibration

@dataclass(frozen=True)
class GroupCompletion:
    finish_cycles: float
    request_states: tuple[str, ...]
    newly_fetched_sectors: int

@dataclass
class GroupReadiness:
    response: ProbeResponseCalibration = field(default_factory=ProbeResponseCalibration.measured)
    sector_ready: dict[int, float] = field(default_factory=dict)

    def issue(self, start_cycles: float, requests: list[tuple[int, int]]) -> GroupCompletion:
        if start_cycles<0 or len(requests)!=4:
            raise ValueError('Only nonnegative times and four-request groups are validated.')
        if any(len(r)!=2 or len(set(r))!=2 or any(s<0 for s in r) for r in requests):
            raise ValueError('Each validated request accesses two distinct 32-byte sectors.')
        flattened=[s for r in requests for s in r]
        if len(set(flattened))!=8:
            raise ValueError('Within-group sector repetition is outside the measured probe.')
        states=[]
        for r in requests:
            sector_states=['new' if s not in self.sector_ready else
                           'pending' if self.sector_ready[s]>start_cycles else 'ready' for s in r]
            if len(set(sector_states))!=1:
                raise ValueError('Partial-sector readiness within a request is unvalidated.')
            states.append(sector_states[0])
        pending=[self.sector_ready[s] for s in flattened if s in self.sector_ready and self.sector_ready[s]>start_cycles]
        if pending:
            if states!=['pending']*4 or len(set(pending))!=1:
                raise ValueError('Partial pending groups need a further response experiment.')
            warm=self.response.window_cycles(4,['L2']*4)
            # Validated at simultaneous issue or already-ready endpoints;
            # arbitrary intermediate skew is an explicitly labeled extrapolation.
            if abs(start_cycles-(pending[0]-self.response.window_cycles(4,['external']*4)))>1e-6:
                raise ValueError('Intermediate pending-arrival skew remains unvalidated.')
            finish=max(start_cycles+warm,max(pending))
        else:
            outcomes=['external' if s=='new' else 'L2' for s in states]
            finish=start_cycles+self.response.window_cycles(4,outcomes)
        new_sectors=[s for s in flattened if s not in self.sector_ready]
        # Group completion is a conservative shared availability point. This
        # does not assert equal intrinsic return time for every request.
        for s in new_sectors:self.sector_ready[s]=finish
        return GroupCompletion(finish,tuple(states),len(new_sectors))

    def invalidate(self, sectors: list[int]):
        for s in sectors:self.sector_ready.pop(s,None)
