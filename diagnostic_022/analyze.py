from pathlib import Path
import csv,json,re
p=Path(__file__).parent
def raw(path):
    rows=list(csv.reader(path.open()))
    i=next(i for i,r in enumerate(rows) if r and r[0]=='ID')
    names,units,values=rows[i:i+3]
    result={}
    for name,unit,value in zip(names,units,values):
        try: number=float(value.replace(',',''))
        except ValueError: continue
        factor={'us':1000,'ms':1000000,'s':1000000000,'Kbyte':1000,'Mbyte':1000000,'Gbyte':1000000000,'KHz':1000,'MHz':1000000,'GHz':1000000000,'Ghz':1000000000,'Mhz':1000000,'Khz':1000}.get(unit,1)
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



def gemm_instructions(path):
 s=path.read_text().split('Function : _Z4gemm',1)[1].split('Function :',1)[0]
 return [x.split(';')[0].strip() for x in s.splitlines() if re.match(r'\s*/\*[0-9a-f]+\*/',x)]

def source_counts(path):
 lines=path.read_text().splitlines();i=next(i for i,x in enumerate(lines) if x.startswith('"Address"'));rows=list(csv.DictReader(lines[i:]));pending={};groups=[];hmma=0;executed=0
 for r in rows:
  n=float((r.get('Instructions Executed') or '0').replace(',',''))
  if not n:continue
  executed+=n;src=r['Source'].strip();registers=re.findall(r'\bR\d+\b',src)
  if 'HMMA.' in src:hmma+=n
  if r['Address Space']=='Global' and r['Access Operation']=='Load':
   assert float(r['Avg. Predicated-On Threads Executed'])==32
   pending[registers[0]]=n
  elif r['Address Space']=='Shared' and r['Access Operation']=='Store' and registers and registers[-1] in pending:
   assert len(set(pending.values()))==1
   groups.append({'width':len(pending),'multiplicity':next(iter(pending.values()))});pending={}
 assert not pending
 return {'groups':groups,'hmma_warp_instructions':hmma,'all_warp_instructions':executed}

d=json.loads((p/'measurements.json').read_text());assert len(d)==8 and all(x['correct'] and x['local_bytes_thread']==0 for x in d)
frozen=json.loads((p/'frozen_predictions.json').read_text())['predictions'];profiles=[];by={}
for bm,bn in [(32,32),(64,48)]:
 assert gemm_instructions(p/f'gemm_{bm}_{bn}.sass')==gemm_instructions(p/f'original_{bm}_{bn}.sass')
 for warm in [0,1]:
  name=f'profile_{bm}_{bn}_k16384_c{warm}';a=raw(p/f'{name}.raw.csv');src=source_counts(p/f'{name}.source.csv');stages=16384/32;blocks=(64/bm)*(96/bn);pred=next(x for x in frozen if x['tile']==[bm,bn,32])
  reads=a['lts__t_sectors_srcunit_tex_op_read_lookup_hit.sum']+a['lts__t_sectors_srcunit_tex_op_read_lookup_miss.sum'];hit=a['lts__t_sectors_srcunit_tex_op_read_lookup_hit.sum'];miss=a['lts__t_sectors_srcunit_tex_op_read_lookup_miss.sum'];l1hit=a['l1tex__t_sectors_pipe_lsu_mem_global_op_ld_lookup_hit.sum'];l1total=l1hit+a['l1tex__t_sectors_pipe_lsu_mem_global_op_ld_lookup_miss.sum'];expectedmiss=0 if warm else (64+96)*16384*2/32
  bank_total=a['memory_l1_wavefronts_shared']-a['l1tex__data_pipe_lsu_wavefronts_mem_shared_cmd_write.sum'];expectedbank=pred['bank_service_cycles']*blocks*stages+192
  windows=sum(x['multiplicity'] for x in src['groups'])/(blocks*4*stages);requests=sum(x['width']*x['multiplicity'] for x in src['groups']);hmma=64*96*16384/(16*16*16)*2
  ordinary=next(x for x in d if x['tile']==[bm,bn,32] and x['shape'][2]==16384 and x['warm']==warm)['median_ms'];profile_ms=a['gpu__time_duration.sum']/1e6 # normalized nanoseconds below
  freq=a['sm__cycles_elapsed.avg.per_second'];assert 2e9<freq<4e9
  q={'tile':[bm,bn,32],'warm':warm,'hit_fraction':hit/reads,'miss_sectors':miss,'expected_miss_sectors':expectedmiss,'l1_hit_fraction':l1hit/l1total,'requests':requests,'raw_global_requests':a['l1tex__t_requests_pipe_lsu_mem_global_op_ld.sum'],'windows_per_warp_stage':windows,'read_bank_packages':bank_total,'expected_read_bank_packages':expectedbank,'hmma_count':src['hmma_warp_instructions'],'expected_hmma':hmma,'all_warp_instructions':src['all_warp_instructions'],'frequency_hz':freq,'profile_device_ms':profile_ms,'ordinary_ms':ordinary,'profile_duration_relative_difference':abs(profile_ms-ordinary)/ordinary}
  q['accepted']=abs(miss-expectedmiss)<=max(1,.01*expectedmiss) and l1hit/l1total<=.01 and windows==pred['windows_per_warp_stage'] and requests==q['raw_global_requests'] and bank_total==expectedbank and src['hmma_warp_instructions']==hmma
  profiles.append(q);by[(bm,bn,warm)]=q
slopes=[]
for bm,bn in [(32,32),(64,48)]:
 pr=next(x for x in frozen if x['tile']==[bm,bn,32]);observed={};predicted_mem={}
 for warm in [0,1]:
  a={x['shape'][2]:x['median_ms'] for x in d if x['tile']==[bm,bn,32] and x['warm']==warm};stage_us=(a[16384]-a[4096])*1000/384;frequency=by[(bm,bn,warm)]['frequency_hz']/1e6;label='warm' if warm else 'cold';cy=pr[f'critical_{label}_stage_cycles'];predict_us=cy/frequency
  overlap_us=pr[f'critical_overlap_{label}_stage_cycles']/frequency
  observed[warm]=stage_us;predicted_mem[warm]=(cy-pr['bank_service_cycles']-pr['matrix_progress_cycles'])/frequency
  slopes.append({'tile':[bm,bn,32],'warm':warm,'measured_stage_us':stage_us,'critical_serial_predicted_stage_us':predict_us,'critical_serial_relative_error':abs(predict_us-stage_us)/stage_us,'overlap_predicted_stage_us':overlap_us,'overlap_relative_error':abs(overlap_us-stage_us)/stage_us,'remaining_serial_stage_us':stage_us-predict_us,'average_cache_predicted_stage_us':pr['average_cache_cold_stage_cycles']/frequency if not warm else None})
 delta=observed[0]-observed[1];pdelta=predicted_mem[0]-predicted_mem[1];slopes.append({'tile':[bm,bn,32],'cold_minus_warm_stage_us':delta,'predicted_cold_minus_warm_stage_us':pdelta,'delta_relative_error':abs(pdelta-delta)/delta})
result={'cases':8,'output_checks':360,'all_correct':True,'all_spill_free':True,'gpu_functions_identical':True,'profiles':profiles,'slopes':slopes,'profile_controls_accepted':all(x['accepted'] for x in profiles),'composition_within5percent':all(x['critical_serial_relative_error']<=.05 for x in slopes if 'critical_serial_relative_error' in x),'no_gemm_fit':True,'absolute_full_gemm_model_complete':False}
(p/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
