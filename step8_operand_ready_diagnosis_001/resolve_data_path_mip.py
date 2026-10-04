"""Resolve same four legal paths with independently parameterized direct graph."""
from pathlib import Path
import json,sys
P=Path(__file__).parent;S=P.parent/'step6_data_path_mip_001';f=json.loads((P/'frozen_operand_prediction.json').read_text());c=f['cases'][0]['candidate'];A=c['A_ready_prior'];B=c['B_ready_prior'];C=c['constant_ready_prior'];T=c['special_ready_prior']
source=(P/'base_mip_source_snapshot.py').read_text();source=source.replace("ROOT=Path(__file__).parent",f"ROOT=Path({str(S)!r});DIRECT=Path({str(P)!r});A={A};B={B};C={C};T={T}")
source=source.replace("path=json.loads((ROOT/f'{label}_instructions.json').read_text());events=[]", "path=json.loads((ROOT/f'{label}_instructions.json').read_text());events=[];operand_by_index={};ordinal=0\n    for index,i in enumerate(path):\n        if i['kind']==1:\n            operand_by_index[index]=[2,2,2,2,1,1,1,1,1,1,2,2,2,2,1,1][ordinal%16];ordinal+=1")
source=source.replace("(ROOT/f'{label}.events')", "(DIRECT/f'direct_K3072_A{A}_B{B}_C{C}_T{T}.events'if label=='direct'else ROOT/f'{label}.events')")
source=source.replace("expected={0:1,1:352 if label=='direct'else 340,2:1,3:29,4:32,5:1,6:28+i['packages']}[i['kind']];assert delay==expected", "expected={0:1,1:352 if label=='direct'else 340,2:1,3:29,4:32,5:1,6:28+i['packages']}[i['kind']]\n        if label=='direct':\n            if i['kind']==1:expected=A if operand_by_index[e['index']]==1 else B\n            elif i['pc']in(0x330,0x370,0x730,0x770,0xb00,0xbb0,0x1b0,0x1e0,0x290):expected=C\n            elif i['pc']in(0x320,0x720):expected=T\n        assert delay==expected")
source=source.replace("(ROOT/('integrated_source_cache_mip.json'if policy=='source_cache'else 'cache_layer_model_update.json'if policy!='requested'else'model_representation_audit_v3.json'))", "(DIRECT/'resolved_four_path_mip.json')")
source=source.replace('H=1000000;', 'H=max(g["earliest"]for g in graphs)+1;')
source=source.replace('solve_start=time.perf_counter();', 'for branch,g in enumerate(graphs):m.constraint({finish:1,z[branch]:-sum(g["arcs"][a][2]for a in g["path"])},lo=0)\n    solve_start=time.perf_counter();')
sys.argv=[str(P/'resolve_data_path_mip.py')];exec(compile(source,str(P/'resolve_data_path_mip.py'),'exec'),{'__name__':'__main__','__file__':str(P/'resolve_data_path_mip.py')})
