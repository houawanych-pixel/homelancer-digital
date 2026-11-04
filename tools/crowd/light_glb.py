#!/usr/bin/env python3
"""Crowd copies of rigged characters (v11.84): keep the mesh, rig and animations; the colour map shrinks to --size px
and every other map (metal/rough, normal, emissive) is dropped, since the crowd's toon shader only reads colour.

    python3 tools/crowd/light_glb.py in.glb out.glb [--size 512]
"""
import io, json, struct, sys
from PIL import Image

def main():
    src, dst = sys.argv[1], sys.argv[2]
    size = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 512
    b = open(src, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    bin0 = 20 + jl + 8
    data = b[bin0:]
    color_imgs = set()
    for m in j.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        if "baseColorTexture" in pbr: color_imgs.add(j["textures"][pbr["baseColorTexture"]["index"]]["source"])
        pbr.pop("metallicRoughnessTexture", None)
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"): m.pop(k, None)
    views = []
    img_view = {im["bufferView"]: i for i, im in enumerate(j.get("images", []))}
    for vi, bv in enumerate(j["bufferViews"]):
        d = data[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        if vi in img_view:
            ii = img_view[vi]
            im = Image.open(io.BytesIO(d)).convert("RGB")
            im = im.resize((size, size), Image.LANCZOS) if ii in color_imgs else im.resize((4, 4))
            o = io.BytesIO(); im.save(o, "JPEG", quality=88); d = o.getvalue()
            j["images"][ii]["mimeType"] = "image/jpeg"
        views.append(d)
    out = bytearray()
    for bv, d in zip(j["bufferViews"], views):
        while len(out) % 4: out.append(0)
        bv["byteOffset"] = len(out); bv["byteLength"] = len(d); out += d
    while len(out) % 4: out.append(0)
    j["buffers"] = [{"byteLength": len(out)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(out), 0x004E4942)); f.write(out)

if __name__ == "__main__":
    main()
