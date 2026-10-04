"""Exact bounded integer MILP primitives. No complete-tile catalog."""
import math
import numpy as np
from scipy.optimize import milp,Bounds,LinearConstraint
from scipy.sparse import coo_matrix
class Model:
 def __init__(self):self.names=[];self.lo=[];self.hi=[];self.integer=[];self.rows=[];self.lower=[];self.upper=[];self.bits={}
 def var(self,name,lo,hi,integer=True):
  i=len(self.names);self.names.append(name);self.lo.append(lo);self.hi.append(hi);self.integer.append(int(integer));return i
 def constraint(self,terms,lo=-np.inf,hi=np.inf):self.rows.append(terms);self.lower.append(lo);self.upper.append(hi)
 def encoding(self,x):
  if x in self.bits:return self.bits[x]
  lo,hi=int(self.lo[x]),int(self.hi[x]);bs=[self.var(f'{self.names[x]}.b{k}',0,1) for k in range((hi-lo).bit_length())]
  self.constraint({x:1,**{b:-2**k for k,b in enumerate(bs)}},lo,lo);self.bits[x]=(lo,bs);return lo,bs
 def product(self,x,y,name):
  # Encode the factor with the shorter bounded integer range.
  if self.hi[x]-self.lo[x]>self.hi[y]-self.lo[y]:x,y=y,x
  assert self.integer[x] and self.lo[x]>=0 and self.lo[y]>=0
  z=self.var(name,self.lo[x]*self.lo[y],self.hi[x]*self.hi[y],integer=bool(self.integer[y]));base,bs=self.encoding(x);terms={z:1,y:-base};L,U=self.lo[y],self.hi[y]
  for k,b in enumerate(bs):
   w=self.var(name+f'.w{k}',0,U,integer=False)
   self.constraint({w:1,b:-U},hi=0);self.constraint({w:1,b:-L},lo=0)
   self.constraint({w:1,y:-1,b:-L},hi=-L);self.constraint({w:1,y:-1,b:-U},lo=-U)
   terms[w]=-2**k
  self.constraint(terms,0,0);return z
 def ceil_div_constant_numerator(self,numerator,x,name):
  n=self.var(name,math.ceil(numerator/self.hi[x]),math.ceil(numerator/self.lo[x]));p=self.product(n,x,name+'.covered')
  self.constraint({p:1},lo=numerator);self.constraint({p:1,x:-1},hi=numerator-1);return n,p
 def round_up(self,x,g,name):
  a=self.var(name+'.units',math.ceil(self.lo[x]/g),math.ceil(self.hi[x]/g));z=self.var(name,g*self.lo[a],g*self.hi[a]);self.constraint({z:1,a:-g},0,0)
  self.constraint({z:1,x:-1},0,g-1);return z
 def solve(self,objective,seconds=60,presolve=True):
  r=[];c=[];v=[]
  for i,row in enumerate(self.rows):
   for j,val in row.items():r.append(i);c.append(j);v.append(val)
  mat=coo_matrix((v,(r,c)),shape=(len(self.rows),len(self.names))).tocsc();cost=np.zeros(len(self.names))
  for i,val in objective.items():cost[i]=val
  return milp(cost,integrality=np.array(self.integer),bounds=Bounds(self.lo,self.hi),constraints=LinearConstraint(mat,self.lower,self.upper),options={'time_limit':seconds,'mip_rel_gap':0,'presolve':presolve})
