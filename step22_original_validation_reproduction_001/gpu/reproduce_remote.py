
import pathlib,subprocess,os,json,time,hashlib,ctypes,threading,datetime,sys
mode=sys.argv[1];d=pathlib.Path('/tmp/rtx5090_step22_original_validation_reproduction_001');d.mkdir(exist_ok=True)
exe=pathlib.Path('/home/zhicheng/rtx5090-gemm-milp-20261002-01/diagnostic_057/gemm_32_32');sha=hashlib.sha256(exe.read_bytes()).hexdigest();assert sha=='aaee4f0855dbefb30e0b2a1b74e40cc1e30f50d56899f4108b9b43511d4d6b59'
q=['nvidia-smi','--query-gpu=index,utilization.gpu,memory.used,clocks.sm','--format=csv,noheader,nounits'];before=subprocess.run(q,capture_output=True,text=True,check=True).stdout;line=next(x for x in before.splitlines()if x.strip().startswith('7,'));_,u,m,_=map(int,line.split(','));assert u==0 and m<100
samples=[];stop=False;nv=ctypes.CDLL('libnvidia-ml.so.1');assert nv.nvmlInit_v2()==0;handle=ctypes.c_void_p();assert nv.nvmlDeviceGetHandleByIndex_v2(7,ctypes.byref(handle))==0
nv.nvmlDeviceGetClockInfo.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.POINTER(ctypes.c_uint)]
def poll():
 while not stop:
  clock=ctypes.c_uint();status=nv.nvmlDeviceGetClockInfo(handle,1,ctypes.byref(clock));samples.append({'monotonic':time.monotonic(),'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'smMHz':clock.value,'status':status});time.sleep(.01)
t=threading.Thread(target=poll);t.start();rows=[]
try:
 shapes=[[64,96,k]for k in [64,1536,128,768]]if mode=='small'else [[2048,2112,k]for k in [1536,3072]]
 env=dict(os.environ,CUDA_VISIBLE_DEVICES='7',RESIDENT_CTAS='11')
 for shape in shapes:
  cmd=[str(exe),*map(str,shape),'1','0'];start=time.monotonic();r=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=120);end=time.monotonic();assert r.returncode==0,r.stderr;rows.append({'kind':'originalCUDAevent','shape':shape,'command':cmd,'env':{'CUDA_VISIBLE_DEVICES':'7','RESIDENT_CTAS':'11'},'start_monotonic':start,'end_monotonic':end,'raw_stdout':r.stdout,'raw_stderr':r.stderr,'parsed':json.loads(r.stdout)})
 if mode=='small':
  for k in [64,1536,128,768]:
   log=d/f'small_K{k}_profile.csv';cmd=['/usr/local/cuda-12.8/bin/ncu','--replay-mode','application','--cache-control','none','--clock-control','none','--kernel-name','regex:^gemm','--launch-skip','11','--launch-count','1','--metrics','gpu__time_duration.sum,sm__cycles_elapsed.avg,sm__cycles_elapsed.avg.per_second','--page','raw','--csv','--log-file',str(log),str(exe),'64','96',str(k),'1','0'];start=time.monotonic();r=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=120);end=time.monotonic();assert r.returncode==0,r.stderr;rows.append({'kind':'originalNCUmethod','shape':[64,96,k],'command':cmd,'start_monotonic':start,'end_monotonic':end,'raw_stdout':r.stdout,'raw_stderr':r.stderr,'raw_csv':log.read_text()})
finally:stop=True;t.join();nv.nvmlShutdown()
print(json.dumps({'mode':mode,'start_utc':samples[0]['utc'],'end_utc':samples[-1]['utc'],'binary_sha256':sha,'idle_before':before,'records':rows,'nvml_clock_samples':samples,'telemetry_scope':'10msNVMLhostpoll;reportedcachedclocknotinstantaneouskernelproof','no_recompile':True,'no_clock_settings':True}))
