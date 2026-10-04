"""Evidence-bounded scalar shared-memory service model for RTX 5090.

Parameter provenance: diagnostic_014/service_parameters_v2.json.
Resource composition: diagnostic_017 supports overlapping limits in bank-bound
streams. Its low-bank-demand control retains extra address/sequence cost.
This component predicts service demand, NOT complete GEMM elapsed time.
"""
from collections import defaultdict
from dataclasses import dataclass

@dataclass(frozen=True)
class ScalarSharedService:
 banks: int = 32
 word_bytes: int = 4
 cycles_per_bank_package: float = 1.0
 min_cycles_per_scalar_warp_load: float = 2.0

 def packages(self, byte_addresses: list[int]) -> int:
  if len(byte_addresses) != 32:
   raise ValueError('This model requires one active, full 32-thread warp.')
  if any(a < 0 or a % self.word_bytes for a in byte_addresses):
   raise ValueError('Only aligned 32-bit scalar reads are validated.')
  words = defaultdict(set)
  for address in byte_addresses:
   word = address // self.word_bytes
   words[word % self.banks].add(word)
  # Duplicate reads of one word broadcast; distinct words serialize.
  return max(map(len, words.values()))

 def service_cycles(self, byte_addresses: list[int]) -> float:
  if len(set(byte_addresses)) != 32:
   raise ValueError("Timing rate is measured for32 distinct words, not broadcast loads.")
  return max(self.min_cycles_per_scalar_warp_load,
             self.packages(byte_addresses) * self.cycles_per_bank_package)

 def scalar_stream_service_lower_bound_cycles(self, requests: list[list[int]]) -> float:
  """Resource-work lower bound, excluding address production and waiting.

  Each request contains one aligned 32-bit address per active lane. Resource
  limits overlap across requests: do not sum per-request maxima. Mixed streams
  in diagnostic_017 match this bound, but its pure-low control exceeds the bound
  by 7-9% even at high warp counts. It is not a complete elapsed-time model.
  """
  bank_packages = []
  for addresses in requests:
   self.service_cycles(addresses)  # Validate the measured timing domain.
   bank_packages.append(self.packages(addresses))
  instruction_work = len(requests) * self.min_cycles_per_scalar_warp_load
  bank_work = sum(bank_packages) * self.cycles_per_bank_package
  return max(instruction_work, bank_work)

 def contiguous_vector128_stream_service_cycles(self, warp_loads: int) -> float:
  """Saturated aligned full-warp vector loads; measured in diagnostic_016.

  Each lane reads four consecutive words, and lanes collectively read one
  contiguous 512-byte region. Four packages per load dominate service. This
  does not identify vector instruction issue cost below that bank-work limit.
  """
  if not isinstance(warp_loads, int) or warp_loads < 0:
   raise ValueError('Warp load count must be a nonnegative integer.')
  return warp_loads * 4 * self.cycles_per_bank_package

 def operand_addresses(self, stride_bf16_elements: int) -> list[int]:
  if stride_bf16_elements <= 0 or stride_bf16_elements % 16:
   raise ValueError('Validated compiled operand strides are positive multiples of16.')
  return [2*stride_bf16_elements*(lane//4)+4*(lane%4) for lane in range(32)]

 def gemm_stage(self, bm: int, bn: int, bk: int, padding: int = 0) -> dict:
  if (bm,bn,bk) not in [(32,32,32),(64,48,32)]:
   raise ValueError('Compiled lane mapping validated only for the two tested kernel tiles.')
  loads = (bm//16)*(bn//16)*(bk//16)*4
  a = self.operand_addresses(bk+padding)
  b = self.operand_addresses(bn+padding)
  return {'scalar_loads_per_operand_per_block':loads,
          'read_packages_per_block':loads*(self.packages(a)+self.packages(b)),
          'saturated_read_service_cycles_per_block':max(
              2*loads*self.min_cycles_per_scalar_warp_load,
              loads*(self.packages(a)+self.packages(b))*self.cycles_per_bank_package),
          'scope':'Main-loop operand loads only. No output reads, staging stores, dependencies, clocks, or overlap included.'}

 def probe_cycles(self, row_words: int, warps: int, iterations: int) -> float:
  if warps not in [1,2,4,6,8,12,16] or iterations <= 0:
   raise ValueError('Outside validated warp counts or invalid repetition length.')
  addresses = [4*(row_words*(lane//4)+lane%4) for lane in range(32)]
  packages = self.packages(addresses)
  sequence = max(80.0,64.5+7.9642857142857215*packages)
  service = 4*warps*self.service_cycles(addresses)
  # Sequence coefficients include this probe's address and arithmetic work.
  # They must NOT be treated as individual load latencies or GEMM constants.
  return iterations*max(sequence,service)
