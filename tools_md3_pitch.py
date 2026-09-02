"""Per-frame pitch of an MD3's dominant axis.

Reads every frame, gathers all surface verts, finds the principal axis by
covariance, and reports its pitch in degrees. A barrel-shaped mesh lying
level reads ~0; nose-down reads negative.
"""
import struct, sys, math

def read_md3(path):
    b = open(path, "rb").read()
    num_frames   = struct.unpack_from("<i", b, 76)[0]
    num_surfaces = struct.unpack_from("<i", b, 84)[0]
    ofs_surfaces = struct.unpack_from("<i", b, 100)[0]
    frames = [[] for _ in range(num_frames)]
    o = ofs_surfaces
    for _ in range(num_surfaces):
        name = b[o+4:o+68].split(b"\0")[0].decode("latin1")
        num_verts = struct.unpack_from("<i", b, o+80)[0]
        ofs_xyz   = struct.unpack_from("<i", b, o+96)[0]
        ofs_end   = struct.unpack_from("<i", b, o+104)[0]
        for f in range(num_frames):
            base = o + ofs_xyz + (f*num_verts)*8
            for v in range(num_verts):
                x, y, z = struct.unpack_from("<hhh", b, base + v*8)
                frames[f].append((x/64.0, y/64.0, z/64.0))
        o += ofs_end
    return frames

def principal_pitch(pts):
    n = len(pts)
    if n < 3: return None, 0.0
    cx = sum(p[0] for p in pts)/n
    cy = sum(p[1] for p in pts)/n
    cz = sum(p[2] for p in pts)/n
    # covariance
    c = [[0.0]*3 for _ in range(3)]
    for p in pts:
        d = (p[0]-cx, p[1]-cy, p[2]-cz)
        for i in range(3):
            for j in range(3):
                c[i][j] += d[i]*d[j]
    # power iteration for the dominant eigenvector
    v = [1.0, 0.0, 0.0]
    for _ in range(200):
        w = [sum(c[i][j]*v[j] for j in range(3)) for i in range(3)]
        m = math.sqrt(sum(x*x for x in w))
        if m == 0: break
        v = [x/m for x in w]
    horiz = math.hypot(v[0], v[1])
    pitch = math.degrees(math.atan2(v[2], horiz))
    # axis sign is arbitrary; report the acute answer
    if pitch > 90: pitch -= 180
    if pitch < -90: pitch += 180
    length = max(math.dist(a, b) for a in pts[::max(1, len(pts)//60)]
                                  for b in pts[::max(1, len(pts)//60)])
    return pitch, length

if __name__ == "__main__":
    path = sys.argv[1]
    only = [int(x) for x in sys.argv[2:]] if len(sys.argv) > 2 else None
    frames = read_md3(path)
    print("%-6s %-9s %s" % ("FRAME", "PITCH", "LEN"))
    for i, pts in enumerate(frames):
        if only and i not in only: continue
        p, l = principal_pitch(pts)
        flag = ""
        if abs(p) > 5:  flag = "   <-- pitched"
        if abs(p) > 15: flag = "   <-- PITCHED HARD"
        print("%-6d %+8.2f  %7.1f%s" % (i, p, l, flag))
