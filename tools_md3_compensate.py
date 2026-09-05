"""Given a mesh shift, compute the MODELDEF Offset that keeps the model
where it was. A replica of the engine's static HUD-model matrix.

    python tools_md3_compensate.py --shift SX SY SZ --scale XS YS ZS \
        [--offset OX OY OZ] [--angle A] [--pitch P] [--roll R]

Every line of this mirrors a line of src/r_data/models.cpp (RenderHUDModel)
and src/common/utility/matrix.cpp, read rather than remembered:

  - the MD3 loader hands the buffer (x, z, y): matrix-Y is MD3 up.
    (models_md3.cpp:315  bvert->Set(vert->x, vert->z, vert->y, ...))
  - VSMatrix post-multiplies (M = M*T), so the LAST call in source order is
    applied to the vertex FIRST. Vertex order of the static chain is:
        rotate(-roll,1,0,0)  rotate(pitch,0,0,1)  rotate(-angle,0,1,0)
        rotate(90,0,1,0)
        translate(xoff/xs, zoff/zs, yoff/ys)
        scale(xs, zs, ys)
  - rotate() is glRotate / Rodrigues (matrix.cpp:220).

So world = S * (R * P + T/S) = S*R*P + Off, with Off = (xoff, zoff, yoff)
in matrix order. Shifting the mesh by -c changes world by -S*R*c', where
c' is the shift in matrix order (cx, cz, cy). Compensation:

        Off_new = Off_old + S * R * c'

RUNTIME TERMS ARE NOT IN HERE, deliberately: the hand sliders, bob and
global weapon scale all sit between the vertex and Offset. At their
defaults they are identity and this is exact. With a hand slider turned,
the model now pivots about its own centre instead of a point off the gun
-- which is the point of re-origining, and is why an exact static answer
does not exist for that case.
"""
import sys, math


def rot(angle_deg, x, y, z):
    a = math.radians(angle_deg)
    co, si = math.cos(a), math.sin(a)
    n = math.sqrt(x * x + y * y + z * z); x, y, z = x / n, y / n, z / n
    # column-major mat[] from matrix.cpp, returned as row-major 3x3 for apply()
    m = [[0.0] * 3 for _ in range(3)]
    m[0][0] = co + x * x * (1 - co); m[0][1] = x * y * (1 - co) - z * si; m[0][2] = x * z * (1 - co) + y * si
    m[1][0] = x * y * (1 - co) + z * si; m[1][1] = co + y * y * (1 - co); m[1][2] = y * z * (1 - co) - x * si
    m[2][0] = x * z * (1 - co) - y * si; m[2][1] = y * z * (1 - co) + x * si; m[2][2] = co + z * z * (1 - co)
    return m


def apply(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def compensate(shift_md3, scale, offset=(0, 0, 0), angle=0.0, pitch=0.0, roll=0.0):
    xs, ys, zs = scale
    # MD3 -> matrix order
    c = (shift_md3[0], shift_md3[2], shift_md3[1])
    # vertex order: roll, pitch, angle, then the 90 about Y
    v = apply(rot(-roll, 1, 0, 0), c)
    v = apply(rot(pitch, 0, 0, 1), v)
    v = apply(rot(-angle, 0, 1, 0), v)
    v = apply(rot(90.0, 0, 1, 0), v)
    # scale(xs, zs, ys) in matrix order
    w = (v[0] * xs, v[1] * zs, v[2] * ys)
    # Off in matrix order is (xoff, zoff, yoff)
    xo, yo, zo = offset
    new = (xo + w[0], yo + w[2], zo + w[1])   # back to MODELDEF x y z
    return new, w


def main():
    a = sys.argv[1:]
    def vec(flag, default):
        if flag in a:
            i = a.index(flag); return tuple(float(a[i + k]) for k in (1, 2, 3))
        return default
    def num(flag, default):
        return float(a[a.index(flag) + 1]) if flag in a else default
    shift = vec("--shift", None); scale = vec("--scale", (1, 1, 1)); off = vec("--offset", (0, 0, 0))
    angle, pitch, roll = num("--angle", 0), num("--pitch", 0), num("--roll", 0)
    new, w = compensate(shift, scale, off, angle, pitch, roll)
    print("mesh shift (md3 xyz)      %+8.3f %+8.3f %+8.3f" % shift)
    print("world delta (matrix xyz)  %+8.3f %+8.3f %+8.3f" % w)
    print("Offset %.3f %.3f %.3f" % new)
    print("OFFSET %.6f %.6f %.6f" % new)


if __name__ == "__main__":
    main()
