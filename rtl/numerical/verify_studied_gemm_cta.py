"""Verify one original CTA from real backing values to acknowledged output stores."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from verify_numerical_matrix import no_core

ROOT = Path(__file__).resolve().parent
RTL = ROOT.parent
SOURCES = [RTL/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',
 ROOT/'library_movm_permutation.sv', ROOT/'numerical_matrix_pipeline.sv',
 ROOT/'native_bf16_adapter.sv', RTL/'components/warp_shared_read_service.sv',
 ROOT/'generic_shared_matrix_pipeline.sv', ROOT/'timed_generic_shared_matrix_pipeline.sv',
 ROOT/'studied_gemm_matrix_pipeline.sv', RTL/'components/sector_read_cache.sv',
 RTL/'discovery_rounds/native_barrier_015/native_control_decode.sv',
 RTL/'discovery_rounds/native_barrier_015/producer_barrier_tracker.sv',
 RTL/'components/decoded_native_issue_gate.sv',ROOT/'native_studied_stage_schedule.sv',
 ROOT/'native_movm_word_pipeline.sv',ROOT/'native_hmma16816_adapter.sv',
 ROOT/'native_studied_stage_pipeline.sv', ROOT/'native_multiwarp_stage_pipeline.sv', RTL/'components/cta_generation_barrier.sv', ROOT/'studied_output_scratch_pipeline.sv', ROOT/'coalesced_u16_warp_load.sv',
 ROOT/'studied_gemm_cta_controller.sv', ROOT/'studied_gemm_cta_tb.sv', ROOT/'bf16_reference.cpp']


def run(quick=False, full_only=False, native_stage=False, coalesced=False, coalesced_output=False, multiwarp=False, output_scratch=False, cta_barriers=False):
    if cta_barriers:
        output_scratch = True
    if output_scratch:
        multiwarp = True
    if multiwarp:
        coalesced_output = True
    if coalesced_output:
        coalesced = True
    if coalesced:
        native_stage = True
    configurations = [(32,32,64,2,2), (32,32,64,13,2)]
    if not quick:
        configurations.extend([(32,32,1536,2,1), (64,48,1536,2,1)])
    if full_only:
        configurations = [(32,32,1536,2,1), (64,48,1536,13,1)]
    if native_stage:
        configurations = [case for case in configurations if case[:2]==(32,32)]
    sources = SOURCES + [ROOT/"coalesced_fp32_warp_store.sv"]
    checks = []
    with tempfile.TemporaryDirectory(prefix='studied-cta-') as temporary:
        for bm,bn,k,delay,replays in configurations:
            build = Path(temporary)/f'bm{bm}_bn{bn}_k{k}_d{delay}'
            compile_result = subprocess.run(['verilator','--binary','--timing','-j','2',
                '-Wno-fatal','--top-module','studied_gemm_cta_tb',f'-GBM={bm}',f'-GBN={bn}',
                f'-GK={k}',f'-GREAD_DELAY={delay}',f'-GREPLAYS={replays}',f'-GUSE_NATIVE_STAGE={int(native_stage)}',f'-GCOALESCED_STAGING={int(coalesced)}',f'-GCOALESCED_OUTPUT={int(coalesced_output)}',f'-GMULTIWARP_NATIVE_STAGE={int(multiwarp)}',f'-GUSE_OUTPUT_SCRATCH={int(output_scratch)}',f'-GUSE_CTA_BARRIERS={int(cta_barriers)}','--Mdir',str(build),
                '-CFLAGS','-std=c++20',*map(str,sources)],capture_output=True,text=True)
            (ROOT/f'studied_cta_build_{bm}_{bn}_{k}_{delay}_native{int(native_stage)}_coalesced{int(coalesced)}_output{int(coalesced_output)}_multiwarp{int(multiwarp)}_scratch{int(output_scratch)}_barrier{int(cta_barriers)}.log').write_text(compile_result.stdout+compile_result.stderr)
            assert compile_result.returncode == 0, compile_result.stdout+compile_result.stderr
            command = [str(build/'Vstudied_gemm_cta_tb')]
            result = subprocess.run(command,capture_output=True,text=True,preexec_fn=no_core,timeout=180)
            assert result.returncode == 0,result.stdout+result.stderr
            match = re.search(r'STUDIED_CTA_PASS BM=(\d+) BN=(\d+) K=(\d+) checked_words=(\d+) launches=(\d+) stores=(\d+) acks=(\d+) backing_requests=(\d+) cycles=(\d+) read_delay=(\d+)',result.stdout)
            assert match,result.stdout
            launch_metrics = [dict(zip(["launch_id","completion_cycles","logical_loads","shared_commits","returned_sectors"], map(int, item))) for item in re.findall(r"CTA_LAUNCH_METRICS id=(\d+) completion_cycles=(\d+) logical_loads=(\d+) shared_commits=(\d+) returned_sectors=(\d+)", result.stdout)]
            output_metrics = [dict(zip(["launch_id", "packets", "packet_acks"], map(int, item))) for item in re.findall(r"CTA_OUTPUT_METRICS id=(\d+) packets=(\d+) packet_acks=(\d+)", result.stdout)]
            if coalesced_output:
                assert len(output_metrics)==replays and all(x['packets']==x['packet_acks'] and x['packets']>0 for x in output_metrics),result.stdout
            assert len(launch_metrics)==replays, result.stdout
            matrix_metrics = [dict(zip(["launch_id", "requests", "completions"], map(int,item))) for item in re.findall(r"CTA_MATRIX_METRICS id=(\d+) requests=(\d+) completions=(\d+)",result.stdout)]
            assert len(matrix_metrics)==replays and all(x["requests"]==x["completions"] for x in matrix_metrics),result.stdout
            scratch_metrics=[dict(zip(["launch_id","stores","committed_words","reads","completions"],map(int,item))) for item in re.findall(r"CTA_SCRATCH_METRICS id=(\d+) stores=(\d+) committed_words=(\d+) reads=(\d+) completions=(\d+)",result.stdout)]
            if output_scratch: assert len(scratch_metrics)==replays and all([x["stores"],x["committed_words"],x["reads"],x["completions"]]==[16,1024,32,32] for x in scratch_metrics),result.stdout
            barrier_metrics=[dict(zip(["launch_id","producer_arrivals","consumer_arrivals","releases"],map(int,item))) for item in re.findall(r"CTA_BARRIER_METRICS id=(\d+) producer_arrivals=(\d+) consumer_arrivals=(\d+) releases=(\d+)",result.stdout)]
            if cta_barriers: assert len(barrier_metrics)==replays and all([x["producer_arrivals"],x["consumer_arrivals"],x["releases"]]==[4*k//32,4*k//32,2*k//32] for x in barrier_metrics),result.stdout
            values = list(map(int,match.groups()))
            assert values[:7] == [bm,bn,k,bm*bn*replays,replays,bm*bn*replays,bm*bn*replays]
            expected_cold_sectors = 2*k*(bm+bn)//32
            assert values[7] == expected_cold_sectors, (values[7], expected_cold_sectors)
            checks.append({'BM':bm,'BN':bn,'K':k,'backing_delay_synthetic':delay,'launches':replays,
                'launch_metrics':launch_metrics, 'output_metrics':output_metrics, 'matrix_metrics':matrix_metrics, 'scratch_metrics':scratch_metrics, 'barrier_metrics':barrier_metrics, 'checked_words':values[3],'committed_stores':values[5],'acknowledged_stores':values[6],
                'backing_sector_requests':values[7],'expected_cold_unique_sectors':expected_cold_sectors,'testbench_total_cycles':values[8],'passed':True,'stdout':result.stdout})
            print(json.dumps({'configuration_passed':[bm,bn,k,delay],'checked_words':values[3],'testbench_total_cycles':values[8]}),flush=True)
            if (bm,bn,k,delay) == (32,32,64,2):
                for flag,message in [('wrongbacking','identity'),('wrongstore','identity')]:
                    bad = subprocess.run(command+['+'+flag],capture_output=True,text=True,preexec_fn=no_core,timeout=30)
                    assert bad.returncode != 0 and message in (bad.stdout+bad.stderr).lower(),bad.stdout+bad.stderr
                    checks.append({'rejected':flag,'passed':True,'stdout':bad.stdout+bad.stderr})
    receipt = {'all_passed':True,'checked_output_words':sum(x.get('checked_words',0) for x in checks),
        'checks':checks,'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
        'oracle':'Independent full dot product: original A17/B13 integer patterns with global row-major strides, divide integer sum by256 to exact FP32 bits.',
        'scope':'First CTA; actual sector-backed input values, scalar shared staging, completion-driven reads, all reduction accumulations and actual acknowledged FP32 stores.',
        'protocol_checks':['initial outstanding read canceled by reset and provider flush','read acceptance backpressure',
            'variable backing response delays','store request backpressure and stable payload','store completion delay',
            'all distinct output coordinates verified','all store acknowledgments precede held launch completion','launch replay'],
        'traffic_count_contract':'For these aligned row-major first-CTA fixtures each input element is loaded once; cold unique sectors=2*K*(BM+BN)/32. The K64 replay fits the declared cache and its combined requests equal the cold count. No native warp-coalescing/concurrency claim.',
        'launch_cycle_boundary':'completion_cycles counts rising edges from accepted launch to first observed done, after all output acknowledgments. Excludes reset and held-done overhead; synthetic provider delays and scheduling remain included. Not calibrated hardware runtime.',
        'cycle_metric_boundary':'testbench_total_cycles includes initial canceled launch/reset, launch handshakes and held done; not kernel execution time or hardware runtime.',
        'runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'timing_calibrated':False,'full_gpu_integrated':False,'native_schedule_implemented':False,
        'native_operand_window_enabled':native_stage,
        'coalesced_staging_enabled':coalesced,
        'coalesced_output_enabled':coalesced_output,
        'multiwarp_native_stage_enabled':multiwarp,
        'output_scratch_enabled':output_scratch,
        'cta_barriers_enabled':cta_barriers,
        'native_operand_window_scope':'OnlyBM32BN32BK32;40originalPCs with decodedcontrols,16sharedloads,8MOVM,4HMMA per fragment/stage. Address ALU instructions are precomputed control-only operations; notfullnative kernel replay.' if native_stage else None,
        'proof_registry_fields_closed':0,'remaining':'Serialized staging and service assumptions; no full-grid/multiSM scheduling, physical latency calibration or hardware timing validation.'}
    target = ROOT/(('studied_gemm_cta_native_quick_verification.json' if quick else 'studied_gemm_cta_native_verification.json') if native_stage else ('studied_gemm_cta_quick_verification.json' if quick else 'studied_gemm_cta_verification.json'))
    if coalesced:
        target = ROOT/('studied_gemm_cta_coalesced_quick_verification.json' if quick else 'studied_gemm_cta_coalesced_verification.json')
        receipt['scope']='First CTA; coalesced 32-lane U16 global requests, actual sector returns, atomic masked shared writes, native operand window and acknowledged FP32 stores.'
        receipt['traffic_count_contract'] += ' Coalesced mode groups lanes by unique sectors; sectors serviced serially and vector shared commits idealized, without a physical throughput claim.'
    if coalesced_output:
        target = ROOT/('studied_gemm_cta_coalesced_output_quick_verification.json' if quick else 'studied_gemm_cta_coalesced_output_verification.json')
        receipt['scope'] += ' Output stores are masked32-byte packets, individually checked and acknowledged before done.'
    if multiwarp:
        target = ROOT/('studied_gemm_cta_multiwarp_quick_verification.json' if quick else 'studied_gemm_cta_multiwarp_verification.json')
        receipt['scope'] += ' Four warp-local native operand windows compete for one shared read service, one MOVM service and one HMMA service.'
    if output_scratch:
        target = ROOT/('studied_gemm_cta_output_scratch_quick_verification.json' if quick else 'studied_gemm_cta_output_scratch_verification.json')
        receipt['scope'] += ' Output values now traverse committed shared scratch stores and actual shared-read returns before global retirement.'
    if cta_barriers:
        target = ROOT/('studied_gemm_cta_barriers_quick_verification.json' if quick else 'studied_gemm_cta_barriers_verification.json')
        receipt['scope'] += ' Explicit per-stage producer and completion-driven consumer barrier generations gate matrix admission and operand replacement.'
    target.write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'passed':True,'checked_words':receipt['checked_output_words'],'receipt':str(target)}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--quick',action='store_true')
    parser.add_argument('--full-only',action='store_true')
    parser.add_argument('--native-stage',action='store_true')
    parser.add_argument('--coalesced-staging',action='store_true')
    parser.add_argument('--coalesced-output',action='store_true')
    parser.add_argument('--multiwarp',action='store_true')
    parser.add_argument('--output-scratch',action='store_true')
    parser.add_argument('--cta-barriers',action='store_true')
    args=parser.parse_args()
    run(args.quick,args.full_only,args.native_stage,args.coalesced_staging,args.coalesced_output,args.multiwarp,args.output_scratch,args.cta_barriers)
