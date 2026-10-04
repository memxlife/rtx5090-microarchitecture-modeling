from pathlib import Path
import json,csv,re
p=Path(__file__).parent
def raw(path):
    rows=list(csv.reader(path.open()))
    i=next(i for i,r in enumerate(rows) if r and r[0]=='ID')
    names,units,values=rows[i:i+3]
    result={}
    for name,unit,value in zip(names,units,values):
        try: number=float(value.replace(',',''))
        except ValueError: continue
        factor={'Kbyte':1000,'Mbyte':1000000,'Gbyte':1000000000,'KHz':1000,'MHz':1000000,'GHz':1000000000}.get(unit,1)
        result[name]=number*factor
    return result

def instructions(path):
    s=path.read_text().split('Function : _Z8response',1)[1].split('Function :',1)[0]
    return [x.split(';')[0].strip() for x in s.splitlines() if re.match(r'\s*/\*[0-9a-f]+\*/',x)]

def response_order(path,group):
    lines=instructions(path)
    memory=[line for line in lines if 'LDG.E.U16 ' in line or 'STS.U16 ' in line]
    kinds=['load' if 'LDG.E.U16 ' in line else 'store' for line in memory]
    assert kinds==['load']*group+['store']*group,(path,kinds)
    return {'group':group,'order':kinds,'instructions':memory}



d=json.loads((p/'measurements.json').read_text());assert len(d)==16 and all(x['correct'] and x['local_bytes']==0 for x in d)
assert all(all(len(set(ids))==2 for ids in x['smid_samples']) for x in d)
identical={str(g):instructions(p/f'response_{g}.sass')==instructions(p.parent/'diagnostic_019'/f'response_{g}.sass') for g in [1,4]};assert all(identical.values())
slopes=[]
for g in [1,4]:
 for separate in [0,1]:
  for warm in [0,1]:
   a={x['loads']:x for x in d if (x['group'],x['separate'],x['warm'])==(g,separate,warm)}
   slopes.append({'group':g,'separate':separate,'warm':warm,'block_window_cycles':[(a[8192]['median_block_cycles'][b]-a[2048]['median_block_cycles'][b])/6144*g for b in range(2)]})
profiles=[]
for f in sorted(p.glob('*.raw.csv')):
 a=raw(f);h=a['lts__t_sectors_srcunit_tex_op_read_lookup_hit.sum'];m=a['lts__t_sectors_srcunit_tex_op_read_lookup_miss.sum'];l1h=a['l1tex__t_sectors_pipe_lsu_mem_global_op_ld_lookup_hit.sum'];l1m=a['l1tex__t_sectors_pipe_lsu_mem_global_op_ld_lookup_miss.sum']
 if 'skew' in f.name: expected=.5
 else: expected=1 if '_c1.' in f.name else (.5 if '_s0_' in f.name else 0)
 profiles.append({'file':f.name,'l2_hit_fraction':h/(h+m),'expected_l2_hit_fraction':expected,'l1_hit_fraction':l1h/(l1h+l1m),'accepted':abs(h/(h+m)-expected)<=.01 and l1h/(l1h+l1m)<=.01,'dram_bytes':a['dram__bytes_read.sum'],'global_requests':a['l1tex__t_requests_pipe_lsu_mem_global_op_ld.sum']})
result={'cases':16,'checks':144,'all_correct':True,'all_spill_free':True,'distinct_sms_every_sample':True,'identical_original_gpu_functions':identical,'slopes':slopes,'profiles':profiles,'all_initial_profiles_complete':len([x for x in profiles if 'skew' not in x['file']])==8,'full_model_complete':False}
if (p/'skew_measurements.json').exists():
 sd=json.loads((p/'skew_measurements.json').read_text());assert len(sd)==4 and all(x['correct'] and x['local_bytes']==0 for x in sd)
 assert all(all(len(set(ids))==2 for ids in x['smid_samples']) for x in sd)
 response_order(p/'response_skew_4.sass',4)
 comparisons=[]
 for far in [0,1]:
  a={x['loads']:x for x in sd if x['far']==far}
  observed=[(a[8192]['median_block_cycles'][b]-a[2048]['median_block_cycles'][b])/6144*4 for b in range(2)]
  predicted=[1015.3619791666666,399.4264322916667 if far else 1015.3619791666666]
  comparisons.append({'far':far,'observed_block_window_cycles':observed,'predicted_block_window_cycles':predicted,'relative_errors':[abs(m-pr)/m for m,pr in zip(observed,predicted)]})
 result['skew']={'cases':4,'checks':36,'comparisons':comparisons,'far_delay_exceeds_block0_time':all(x['delay']>x['median_block_cycles'][0] for x in sd if x['far']),'profile_controls_complete':len([x for x in profiles if 'skew' in x['file']])==2,'within5percent':all(e<=.05 for c in comparisons for e in c['relative_errors'])}
 result['readiness_evidence_accepted']=result['all_initial_profiles_complete'] and result['skew']['profile_controls_complete'] and all(x['accepted'] for x in profiles) and result['skew']['within5percent']
(p/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps({'slopes':slopes,'profiles':profiles,'skew':result.get('skew'),'accepted':result.get('readiness_evidence_accepted')},indent=2))
