"""Generate supported native MOVM permutation from measured halfword capture."""
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parent
source=root.parent/'discovery_rounds/functional_mapping_002/analysis.json'
p=json.loads(source.read_text())['movm_post_to_pre_halfword_permutation']
assert sorted(p)==list(range(256))
lines=['// Measured post-MOVM halfword position -> pre-MOVM position.',f'// Evidence SHA256 {hashlib.sha256(source.read_bytes()).hexdigest()}', '// Functional lane/register contents only; no physical latency or routing claim.', 'package library_movm_permutation;', ' function automatic int pre_index(input int post_index);', '  case(post_index)']
lines += [f'   {i}: return {v};' for i,v in enumerate(p)]
lines += ['   default: begin $fatal(1,"MOVM permutation index out of range"); return 0; end','  endcase',' endfunction','endpackage']
(root/'library_movm_permutation.sv').write_text('\n'.join(lines)+'\n')
