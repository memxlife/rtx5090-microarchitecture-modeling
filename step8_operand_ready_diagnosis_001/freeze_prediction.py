"""Freeze separately measured A/B readiness without reading whole-GEMM timings."""
from pathlib import Path
import sys,subprocess,json,datetime,time,hashlib,math
P=Path(__file__).parent;S=P.parent/'step6_data_path_mip_001';sys.path.insert(0,str(S));from extract_instructions import direct_path

def predict(K,A,B,C=1,T=1):
 path=direct_path(K//32);tsv=P/f'direct_K{K}.tsv';events=P/f'direct_K{K}_A{A}_B{B}_C{C}_T{T}.events'
 tsv.write_text('\n'.join(' '.join(map(str,[i['pc'],i['kind'],i['req'],i['wr'],i['rd'],1,len(i['src']),*i['src'],len(i['dst']),*i['dst']]))for i in path)+'\n')
 out=subprocess.check_output(['/private/tmp/operand_executor',str(tsv),str(A),str(B),str(events),str(C),str(T)],text=True);local,n=map(int,out.split());capacity=7607+math.ceil(144*(K//32)*128/48)
 return {'K':K,'A_ready_prior':A,'B_ready_prior':B,'constant_ready_prior':C,'special_ready_prior':T,'instruction_cycles':local,'instructions':n,'completion_cycles':max(local+7607,capacity),'predicted_us_at2940':max(local+7607,capacity)/2940,'cache_scope':'128sourceunique sectors/stage supportedlocaltagproxy, notphysicalcacheparameters','events_sha256':hashlib.sha256(events.read_bytes()).hexdigest()}
if __name__=='__main__':
 assert len(sys.argv)in(4,6),'A B primitive_receipt [constant special] required'
 A,B=map(int,sys.argv[1:3]);C,T=map(int,sys.argv[4:6])if len(sys.argv)==6 else(1,1);receipt=Path(sys.argv[3]);assert receipt.exists();begin=time.perf_counter();rows=[]
 for K in(3072,1024,2048):
  row={'candidate':predict(K,A,B,C,T),'ablations':{'baseline_uniform352':predict(K,352,352),'A_only':predict(K,A,352),'B_only':predict(K,352,B),'AB_only':predict(K,A,B),'constant_only':predict(K,352,352,C,1),'special_only':predict(K,352,352,1,T)}};rows.append(row)
 r={'state':'frozen_before_fresh_confirmation','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'cases':rows,'primitive_receipt':str(receipt),'control_class_priors':{'constant':C,'special':T},'primitive_receipt_sha256':hashlib.sha256(receipt.read_bytes()).hexdigest(),'scope':'A/BcompositebatchreadinessappliedperLD transfer hypothesis. SourceissuesfixedRR, finitequeues/registerownership retained. Unidentified control/issue/queuepriorsunchanged. Fixed7607startup/outputscope transferredfromsourcephase. K3072/K1024repeatedvalidation;K2048previouslyunmeasuredonlyifconfirmedbyGPUagent. No wholetimingfit.','preparation_seconds':time.perf_counter()-begin,'source_sha256':{n:hashlib.sha256((P/n).read_bytes()).hexdigest()for n in('instruction_executor.hpp','run_executor.cpp','freeze_prediction.py')}}
 (P/'frozen_operand_prediction.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
