"""Exact rational arithmetic oracle for finite-normal BF16/FP32 directed cases."""
from fractions import Fraction
from pathlib import Path
import hashlib,json,random,resource,struct,subprocess,tempfile
ROOT=Path(__file__).resolve().parent

def no_core(): resource.setrlimit(resource.RLIMIT_CORE,(0,0))

def decode(bits,fraction_bits):
    sign=-1 if bits>>(fraction_bits+8) else 1
    exponent=(bits>>fraction_bits)&255;mantissa=bits&((1<<fraction_bits)-1)
    assert exponent!=255 and (exponent!=0 or mantissa==0)
    if exponent==0:return Fraction(0)
    shift=exponent-127-fraction_bits
    return sign*Fraction((1<<fraction_bits)+mantissa)*Fraction(2)**shift

def round_fp32(value):
    if not value:return 0
    sign=0x80000000 if value<0 else 0;value=abs(value)
    exponent=value.numerator.bit_length()-value.denominator.bit_length()
    if value<Fraction(2)**exponent:exponent-=1
    assert -126<=exponent<=127
    scaled=value/(Fraction(2)**(exponent-23))
    integer,remainder=divmod(scaled.numerator,scaled.denominator)
    if remainder*2>scaled.denominator or (remainder*2==scaled.denominator and integer%2):integer+=1
    if integer==(1<<24):integer>>=1;exponent+=1
    assert exponent<=127
    return sign|((exponent+127)<<23)|(integer-(1<<23))

def bf16(value):
    bits=struct.unpack('<I',struct.pack('<f',value))[0]
    assert bits&65535==0 # generated inputs are exactly representable
    return bits>>16

def write_vectors(directory,arrays):
    directory.mkdir(parents=True,exist_ok=True)
    for name,values in arrays.items():
        (directory/f'{name}.hex').write_text(''.join(f'{v:08x}\n' for v in values))

def vectors():
    rng=random.Random(5090);arrays={k:[] for k in ['a','b','c','expected']}
    labels=['identity_right','zero_product_nonzero_accumulator','signed_integer',
            'fractional_rounding','cancellation','varied_exponents']
    for case in range(6):
        a=[];b=[];c=[]
        for i in range(256):
            a.append(bf16(0 if case==1 else rng.randint(-30,30)*2.**(-rng.randrange(7) if case in [3,4] else rng.randrange(-12,13) if case==5 else 0)))
            b.append(bf16(int(i//16==i%16) if case==0 else rng.randint(-30,30)*2.**(-rng.randrange(7) if case in [3,4] else rng.randrange(-12,13) if case==5 else 0)))
            c.append(round_fp32(Fraction(0 if case==0 else rng.randint(-20,20),8)))
        # Alternating signs with matching magnitudes stress exact cancellation.
        if case==4:
            for row in range(16):
                for k in range(0,16,2):a[row*16+k+1]=a[row*16+k]
            for k in range(0,16,2):
                for col in range(16):b[(k+1)*16+col]=b[k*16+col]^0x8000
        expected=[]
        for row in range(16):
            for col in range(16):
                result=c[row*16+col]
                for k in range(16):
                    exact=decode(a[row*16+k],7)*decode(b[k*16+col],7)+decode(result,23)
                    result=round_fp32(exact)
                expected.append(result)
        for key,values in [('a',a),('b',b),('c',c),('expected',expected)]:arrays[key].extend(values)
    return arrays,labels

def run():
    arrays,labels=vectors();directory=ROOT/'vectors';write_vectors(directory,arrays)
    sources=[ROOT/'numerical_matrix_pipeline.sv',ROOT/'numerical_matrix_tb.sv',ROOT/'bf16_reference.cpp']
    tool='verilator';checks=[]
    with tempfile.TemporaryDirectory(prefix='rtx-matrix-') as tmp:
        for latency,interval in [(2,1),(17,3)]:
            build=Path(tmp)/f'latency_{latency}'
            command=[tool,'--binary','--timing','-Wno-fatal','--top-module','numerical_matrix_tb',
                     f'-GLATENCY={latency}',f'-GINTERVAL={interval}','--Mdir',str(build),
                     '-CFLAGS','-std=c++20',*[str(p) for p in sources]]
            result=subprocess.run(command,text=True,capture_output=True)
            (ROOT/f'build_{latency}.log').write_text(result.stdout+result.stderr)
            assert result.returncode==0,result.stdout+result.stderr
            binary=build/'Vnumerical_matrix_tb'
            result=subprocess.run([str(binary),f'+vectors={directory}'],text=True,capture_output=True,preexec_fn=no_core)
            assert result.returncode==0 and 'NUMERICAL_MATRIX_PASS' in result.stdout,result.stdout+result.stderr
            checks.append({'latency_baseline_cycles':latency,'interval_baseline_cycles':interval,'passed':True,'output':result.stdout})
            if latency==17:
                result=subprocess.run([str(binary),f'+vectors={directory}','+duplicate'],text=True,capture_output=True,preexec_fn=no_core)
                assert result.returncode!=0 and 'Duplicate pending matrix identity' in result.stdout+result.stderr
                checks.append({'rejected':'duplicate_pending_identity','passed':True})
                for label,word in [('nan',0x7fc0),('subnormal',1)]:
                    bad=dict(arrays);bad['a']=arrays['a'].copy();bad['a'][0]=word
                    bad_dir=Path(tmp)/label;write_vectors(bad_dir,bad)
                    result=subprocess.run([str(binary),f'+vectors={bad_dir}'],text=True,capture_output=True,preexec_fn=no_core)
                    assert result.returncode!=0 and 'Unsupported reference arithmetic' in result.stdout+result.stderr
                    checks.append({'rejected':label,'passed':True})
    receipt={'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
             'vector_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.glob('*.hex')},
             'verilator_version':subprocess.check_output([tool,'--version'],text=True).strip(),
             'oracle':'Exact rational BF16 products plus FP32 accumulator; round nearest even after each reduction element',
             'case_labels':labels,'checks':checks,'all_passed':True,
             'checked_output_words':3072,'hardware_calibrated':False,'native_tensor_accumulation_order_identified':False,
             'full_gemm_model':False,'unsupported':['nonfinite/subnormal operands or results','native lane mapping','multiple SM/block scheduling']}
    (ROOT/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(f'Numerical matrix verification passed: {len(checks)} cases, 3072 checked FP32 output words; timing remains synthetic.')

if __name__=='__main__':run()
