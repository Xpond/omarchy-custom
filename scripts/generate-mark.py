"""Generate the wheel's mask, path distances, and bevel. Needs NumPy and ImageMagick."""
from collections import deque
from pathlib import Path
import subprocess
import sys

import numpy as np

SRC = "/usr/share/omarchy/icon.png"
UP = 4
T = int(sys.argv[1]) if len(sys.argv) > 1 else 4
OUT = (sys.argv[2] if len(sys.argv) > 2 else
       str(Path(__file__).resolve().parents[1] / "plugins/xpo.wheel/mark.png"))

raw=subprocess.check_output(["magick",SRC,"-depth","8","rgba:-"])
a=np.frombuffer(raw,dtype=np.uint8).reshape(300,300,4)
ink=np.repeat(np.repeat(a[...,3]>128,UP,axis=0),UP,axis=1)
H,W=ink.shape

def run(m,axis,rev):
    m2=np.flip(m,axis=axis) if rev else m
    o=np.zeros(m.shape,np.int32); acc=np.zeros(m.shape[1-axis],np.int32)
    for i in range(m.shape[axis]):
        row=m2[i,:] if axis==0 else m2[:,i]
        acc=np.where(row,acc+1,0)
        if axis==0: o[i,:]=acc
        else: o[:,i]=acc
    return (np.flip(o,axis=axis) if rev else o)-1

up,down=run(ink,0,False),run(ink,0,True)
left,right=run(ink,1,False),run(ink,1,True)
vt,ht=up+down+1,left+right+1
BAR=int(np.min(np.minimum(vt,ht)[ink])); print(f"bar thickness = {BAR}px at {W}px")

# centreline of a bar: centred in its own cross-section, and that cross-section
# is a bar thickness (not a junction, where it runs the length of the crossing bar)
cH = ink & (np.abs(up-down)<=T) & (vt<=BAR*1.5)
cV = ink & (np.abs(left-right)<=T) & (ht<=BAR*1.5)

def bridge(c, ink, axis):
    """close gaps in a centreline, but only where the source mask is solid across
    them -- a junction is filled ink, the logo's own breaks are not."""
    out=c.copy()
    for i in range(c.shape[1-axis]):
        line = out[i,:] if axis==1 else out[:,i]
        src  = ink[i,:] if axis==1 else ink[:,i]
        idx=np.flatnonzero(line)
        if idx.size<2: continue
        for x0,x1 in zip(idx[:-1],idx[1:]):
            if x1-x0>1 and src[x0+1:x1].all(): line[x0+1:x1]=True
    return out

def extend(c, ink, axis, cap):
    """carry each centreline on into a corner block, far enough to reach the
    crossing and no further. An L corner has no centreline on its far side to
    bridge to, so it stays open otherwise; unbounded, the line instead runs the
    length of the block and out to the mark's edge, turning every corner into a
    plus. The centreline stops half a bar short of the crossing, so half a bar
    is exactly the distance to travel. A free bar end stops where the ink does."""
    out=c.copy()
    for i in range(c.shape[1-axis]):
        line = out[i,:] if axis==1 else out[:,i]
        src  = ink[i,:] if axis==1 else ink[:,i]
        idx=np.flatnonzero(line)
        if not idx.size: continue
        splits=np.flatnonzero(np.diff(idx)>1)
        starts=np.r_[idx[0], idx[splits+1]]; ends=np.r_[idx[splits], idx[-1]]
        for s0,e0 in zip(starts,ends):
            for step,x0 in ((-1,s0-1),(1,e0+1)):
                x=x0
                while 0<=x<line.size and src[x] and abs(x-x0)<cap:
                    line[x]=True
                    x+=step
    return out

cH=bridge(cH,ink,1); cV=bridge(cV,ink,0)
cH2=extend(cH,ink,1,BAR//2); cV2=extend(cV,ink,0,BAR//2)
keep=(cH2|cV2)&ink
print(f"T={T}: coverage {ink.mean():.4f} -> {keep.mean():.4f}")

# --- how far along the maze each pixel is -------------------------------
# The reveal draws the mark rather than washing it in, so every stroke pixel
# needs to know its own distance along the path from where the drawing starts.
# That is a geodesic, not a radius: a BFS that can only travel down the strokes.
# Each connected piece is seeded at its own innermost pixel, so the drawing
# starts against the wheel and runs outward through the labyrinth, and every
# piece starts at once instead of waiting for a front that can never reach it.
ys,xs=np.nonzero(keep)
NB=[(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]
seen=np.zeros(keep.shape,bool); comp=[]
for y0,x0 in zip(ys,xs):
    if seen[y0,x0]: continue
    q=deque([(y0,x0)]); seen[y0,x0]=True; cur=[]
    while q:
        y,x=q.popleft(); cur.append((y,x))
        for dy,dx in NB:
            ny,nx=y+dy,x+dx
            if 0<=ny<H and 0<=nx<W and keep[ny,nx] and not seen[ny,nx]:
                seen[ny,nx]=True; q.append((ny,nx))
    comp.append(cur)
print(f"{len(comp)} connected piece(s): sizes {sorted(len(c) for c in comp)[-6:]}")

dist=np.full(keep.shape,-1,np.int32)
cy=cx=H//2
for cur in comp:
    sy,sx=min(cur,key=lambda p:(p[0]-cy)**2+(p[1]-cx)**2)
    q=deque([(sy,sx)]); dist[sy,sx]=0
    while q:
        y,x=q.popleft(); d=dist[y,x]+1
        for dy,dx in NB:
            ny,nx=y+dy,x+dx
            if 0<=ny<H and 0<=nx<W and keep[ny,nx] and dist[ny,nx]<0:
                dist[ny,nx]=d; q.append((ny,nx))
mx=dist.max(); print(f"longest run along the maze: {mx}px")
prog=np.where(keep, dist/max(mx,1), 0.0)

# Spread the progress a few pixels into the background. The shader samples this
# with linear filtering, and at a stroke's edge that would otherwise mix the
# stroke's own value with the zero outside it, reading as drawn-too-early.
sp=prog.copy(); m=keep.copy()
for _ in range(3):
    g=sp.copy(); gm=m.copy()
    for dy,dx in NB:
        sh=np.roll(np.roll(sp,dy,0),dx,1); shm=np.roll(np.roll(m,dy,0),dx,1)
        take=shm&~m&(sh>g); g=np.where(take,sh,g); gm|=take
    sp,m=g,gm

# Round the relief without changing coverage. A small Gaussian smooths the
# height at corners too; its gradient gives the surface normal for lighting.
height=keep.astype(float)
for axis in (0,1):
    height=sum(np.roll(height,offset,axis)*weight
               for offset,weight in zip(range(-2,3),(1,4,6,4,1)))/16
dy,dx=np.gradient(height)
normal=np.stack((-dx*3,-dy*3,np.ones_like(height)),axis=-1)
normal/=np.linalg.norm(normal,axis=-1,keepdims=True)

out=np.zeros((H,W,4),np.uint8)
out[...,0]=np.clip(np.rint(sp*255),0,255)   # R: distance along the maze
out[...,1:3]=np.rint((normal[...,:2]*0.5+0.5)*255)  # GB: bevel normal XY
out[...,3]=np.where(keep,255,0)
subprocess.run(["magick","-size",f"{W}x{H}","-depth","8","rgba:-","PNG32:"+OUT],
               input=out.tobytes(),check=True)
print("wrote",OUT)
