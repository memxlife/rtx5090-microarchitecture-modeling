from pathlib import Path
import json
D=Path(__file__).resolve().parent;rows=json.load(open(D.parent/'staging_cpp_repair/producer_path.json'))['rows'];s=f'localparam int PATH_LEN={len(rows)};\n'
for name in ['pc','kind','req','wr','rd','group','src','dst']:
 typ='logic[63:0]'if name in['src','dst']else'int';s+=f'function automatic {typ} op_{name}(input int idx);\ncase(idx)\n'
 for j,r in enumerate(rows):
  v=r[name]; val=f"64'h{sum(1<<i for i in set(v)):016x}"if isinstance(v,list)else str(v);s+=f'{j}:return {val};\n'
 s+=f"default:return {'0' if name in ['src','dst'] else '-1'};\nendcase\nendfunction\n"
(D/'producer_tables.svh').write_text(s)
