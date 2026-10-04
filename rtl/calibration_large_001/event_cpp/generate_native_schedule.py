from pathlib import Path
import re
p=Path(__file__).resolve().parents[2]
s=(p/'numerical/native_studied_stage_schedule.sv').read_text()
a=[]
for raw,kind,b,k,w,h in re.findall(r"d.raw=128'h([0-9a-f]+);d.kind=2'd(\d);d.operand_b=1'b(\d);d.kk=1'b(\d);d.word_index=2'd(\d);d.upper_half=1'b(\d)",s):
 x=int(raw,16);a.append(f' {{{kind},{b},{k},{w},{h},{(x>>105)&15},{(x>>110)&7},{(x>>113)&7},{(x>>116)&63}}}')
out=p/'calibration_large_001/event_cpp/native_schedule.hpp'
out.write_text('#pragma once\n#include <array>\nnamespace native_event {\nstruct Descriptor {int kind,b,k,word,half,delay,write_barrier,read_barrier,wait;};\ninline constexpr std::array<Descriptor,40> schedule={{\n'+',\n'.join(a)+'\n}};\n}\n')
