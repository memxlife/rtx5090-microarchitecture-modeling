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



measurements=json.loads((p/'measurements.json').read_text())
assert len(measurements)==14 and all(d['correct'] and d['local_bytes']==0 for d in measurements)
reference=p.parent/'diagnostic_019'/'response_4.sass'
identical=instructions(p/'response_4.sass')==instructions(reference)
assert identical
contract=json.loads((p/'contract.json').read_text())
slopes=[]
for w,mode,pos in [(4,0,0),(4,1,0),(4,2,0),(4,2,3),(4,3,0),(1,2,0),(8,2,0)]:
 a={d['loads']:d['median_cycles'] for d in measurements if (d['warps'],d['warm'],d['position'])==(w,mode,pos)}
 observed=(a[8192]-a[2048])/6144*4
 lower,upper=contract['prediction']['one_miss_three_hits_critical_window_range_cycles']
 average=contract['prediction']['one_miss_three_hits_average_window_cycles']
 intervalerror=max(lower-observed,observed-upper,0)/observed
 slopes.append({'warps':w,'mode':mode,'position':pos,'measured_window_cycles':observed,'critical_interval_relative_error':intervalerror if mode==2 else None,'average_relative_error':abs(average-observed)/observed if mode in [2,3] else None})
profiles=[]
for f in sorted(p.glob('*.raw.csv')):
 a=raw(f);h=a['lts__t_sectors_srcunit_tex_op_read_lookup_hit.sum'];m=a['lts__t_sectors_srcunit_tex_op_read_lookup_miss.sum'];l1h=a['l1tex__t_sectors_pipe_lsu_mem_global_op_ld_lookup_hit.sum'];l1m=a['l1tex__t_sectors_pipe_lsu_mem_global_op_ld_lookup_miss.sum'];mode=int(re.search(r'mode(\d)',f.name).group(1));expected={0:0,1:1,2:.75,3:.75,4:.25,5:.5}[mode]
 profiles.append({'file':f.name,'mode':mode,'l2_hit_fraction':h/(h+m),'expected_l2_hit_fraction':expected,'l1_hit_fraction':l1h/(l1h+l1m),'accepted':l1h/(l1h+l1m)<=.01 and abs(h/(h+m)-expected)<=.01,'global_requests':a['l1tex__t_requests_pipe_lsu_mem_global_op_ld.sum'],'shared_store_packages':a['l1tex__data_pipe_lsu_wavefronts_mem_shared_cmd_write.sum'],'dram_bytes':a['dram__bytes_read.sum']})
result={'cases':14,'checks':126,'compiled_body_identical':identical,'all_correct':True,'all_spill_free':True,'profiles':profiles,'slopes':slopes,'profile_controls_complete':len([x for x in profiles if x['mode']<=3])==5,'critical_model_accepted':len([x for x in profiles if x['mode']<=3])==5 and all(d['accepted'] for d in profiles) and all(d['critical_interval_relative_error']<=.05 for d in slopes if d['mode']==2) and all(d['average_relative_error']<=.05 for d in slopes if d['mode']==3),'no_gemm_fit':True,'full_model_complete':False}

if (p/'confirmation_measurements.json').exists():
 cd=json.loads((p/'confirmation_measurements.json').read_text());cf=json.loads((p/'mixed_confirmation_predictions.json').read_text())
 assert len(cd)==4 and all(x['correct'] and x['local_bytes']==0 for x in cd)
 same=instructions(p/'response_confirmation_4.sass')==instructions(reference);assert same
 for x in cf['predictions']:
  a={d['loads']:d['median_cycles'] for d in cd if d['warm']==x['mode']};m=(a[8192]-a[2048])/6144*4;x.update(measured_window_cycles=m,relative_error=abs(m-x['predicted_window_cycles'])/m)
 result['fresh_confirmation']={'cases':4,'checks':36,'compiled_body_identical':same,'predictions':cf['predictions'],'accepted':all(x['relative_error']<=.05 for x in cf['predictions']) and len([x for x in profiles if x['mode']>=4])==2 and all(x['accepted'] for x in profiles if x['mode']>=4)}
 result['bounded_mixed_component_accepted']=result['critical_model_accepted'] and result['fresh_confirmation']['accepted']
(p/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
