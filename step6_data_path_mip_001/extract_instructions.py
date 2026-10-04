"""Fixed-shape source CFG expansion; no measured issue timestamps."""
from pathlib import Path
import re,json,hashlib,sys
ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT.parent/'mip_microarchitecture_001'))
from formulate import descriptors
LOADS=[d for d in descriptors()if d[0]==1]

def parse(text,direct=False):
    ins={}
    for line in text.splitlines():
        m=re.search(r'/\*([0-9a-f]+)\*/\s+(.*?)\s*(?:/\*|$)',line)
        if not m:continue
        pc=int(m[1],16);s=m[2];parts=s.split('&')[0].split('?')[0].strip()
        if parts.startswith('@'):_,parts=parts.split(None,1)
        op,args=parts.split(None,1)if' 'in parts else(parts,'');base=op.split('.')[0];operands=args.split(',')
        dest=[]
        if base not in ['STS','STG','BRA','BAR','BSSY','BSYNC','NOP','EXIT','WARPSYNC']:
            dest=[int(x)for x in re.findall(r'(?<![A-Z])R(\d+)\b',operands[0])];read=','.join(operands[1:])
            if('.WIDE'in op or'.64'in op)and dest:dest.append(dest[0]+1)
        else:read=args
        src=[int(x)for x in re.findall(r'(?<![A-Z])R(\d+)\b',read)]
        for x in re.findall(r'(?<![A-Z])R(\d+)\.64',read):src.append(int(x)+1)
        if base=='HMMA':
            regs=[int(x)for x in re.findall(r'(?<![A-Z])R(\d+)\b',args)];assert len(regs)==4
            dest=list(range(regs[0],regs[0]+4));src=list(range(regs[1],regs[1]+4))+list(range(regs[2],regs[2]+2))+list(range(regs[3],regs[3]+4))
        req=re.search(r'&req=\{([^}]+)\}',s);wr=re.search(r'&wr=0x([0-9a-f]+)',s);rd=re.search(r'&rd=0x([0-9a-f]+)',s)
        kind=1 if base=='LDG'or(base=='LD'and direct)else 6 if base=='LD'else 2 if base=='STS'else 3 if base=='MOVM'else 4 if base=='HMMA'else 5 if base=='BAR'else 0
        ins[pc]={'pc':pc,'opcode':op,'kind':kind,'src':sorted(set(src)),'dst':dest,'req':sum(1<<int(x)for x in req[1].split(','))if req else 0,'wr':int(wr[1],16)if wr else-1,'rd':int(rd[1],16)if rd else-1,'text':line.strip()}
    return ins

def direct_path(stages=96):
    assert stages%2==0
    source=ROOT/'direct.sass';ins=parse(source.read_text(),True)
    # Both stages execute: @P0 at0310/0710 tests tid>127, false.
    prologue=[ins[p]for p in sorted(ins)if 0x1b0<=p<0x310]
    body=[ins[p]for p in sorted(ins)if 0x310<=p<=0xb90]
    tail=[ins[p]for p in sorted(ins)if 0xba0<=p<=0xbf0]
    path=prologue+body*(stages//2)+tail
    assert sum(i['kind']==1 for i in path)==16*stages
    return path

def staged_path(stride,stages=96):
    source=ROOT.parent/'step2_layout_gpu_001'/'benchmark.sass';text=source.read_text().split(f'Function : _Z11layout_gemmILi{stride}EE')[1].split('Function :')[0];ins=parse(text)
    start=0x230;bar=min(pc for pc,x in ins.items()if pc>start and x['kind']==5)
    backs=[]
    for pc,x in ins.items():
        if start<=pc<bar and'BRA'in x['opcode']:
            target=int(re.search(r'BRA (0x[0-9a-f]+)',x['text'])[1],16)
            if target<pc:backs.append((pc,target))
    skip=[]
    for a,z in[(start,backs[0][1]),(backs[0][0]+16,backs[1][1])]:
        pc=min(pc for pc,x in ins.items()if a<=pc<z and'@!P0 BRA'in x['text']);target=int(re.search(r'BRA (0x[0-9a-f]+)',ins[pc]['text'])[1],16);skip.append((pc,target))
    end=next(pc for pc,x in sorted(ins.items())if pc>bar and'BRA 0x230'in x['text'])
    single=[];pc=start;seen={a:0 for a,_ in backs}
    while pc<=end:
        single.append(ins[pc])
        if pc in dict(skip):pc=dict(skip)[pc];continue
        if pc in dict(backs):
            seen[pc]+=1
            if seen[pc]==1:pc=dict(backs)[pc];continue
        pc+=16
    assert sum(x['kind']==1 for x in single)==16
    assert sum(x['kind']==6 for x in single)==16
    assert sum(x['kind']==4 for x in single)==4
    return single*stages

if __name__=='__main__':
    records=[]
    for label in ['staged32','staged48','staged64','direct']:
        path=direct_path()if label=='direct'else staged_path(int(label[6:]))
        lines=[];loadordinal=0
        for x in path:
            x['packages']=1
            if x['kind']==6:
                d=LOADS[loadordinal%16];loadordinal+=1;stride=int(label[6:]);banks=[set()for _ in range(32)]
                for lane in range(32):
                    a=2048+2*stride*(16*d[2]+lane//4+8*(d[3]%2))+4*(lane%4)+16*(d[3]//2)if d[1]else 64*(lane//4)+32*d[2]+4*(lane%4)+512*(d[3]%2)+16*(d[3]//2)
                    banks[a//4%32].add(a)
                x['packages']=max(map(len,banks))
            lines.append(' '.join(map(str,[x['pc'],x['kind'],x['req'],x['wr'],x['rd'],x['packages'],len(x['src']),*x['src'],len(x['dst']),*x['dst']])))
        (ROOT/f'{label}.tsv').write_text('\n'.join(lines)+'\n');(ROOT/f'{label}_instructions.json').write_text(json.dumps(path)+'\n')
        records.append({'label':label,'instructions_per_warp':len(path),'counts':{k:sum(x['kind']==k for x in path)for k in range(7)}})
    (ROOT/'executed_path_contract.json').write_text(json.dumps({'scope':'Fixedfullyinbounds128threadK3072; direct48two-stageiterationsandnotail. Perwarp pathsidentical branchdecisionsbutvalues/addressesdiffer. Predicate/uniformregisterdependenciesnotfullymodeled; encodedtrans/WAITdelaysuntranslated. Sourcepriorissuewidth andALUlatency explicit.','paths':records},indent=2)+'\n');print(records)
