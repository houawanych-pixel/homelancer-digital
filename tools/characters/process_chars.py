"""Cut the owner's green-screen character art out: usage python3 tools/characters/process_chars.py <folder with faction subfolders>.
Masters (full size, transparent) -> art/characters/<faction>/, game copies (half-size body, 512 px portrait) -> assets/characters/<faction>/."""
import os, sys, json, glob
from multiprocessing import Pool
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from key_green import key
R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def one(src):
    fac = src.split('/')[-2]; name = os.path.basename(src)[:-4]
    cid, kind = (name[:-len('_full_body')], 'full_body') if name.endswith('_full_body') else (name[:-len('_thigh_up_square')], 'thigh_up_square')
    im = key(src)
    a = np.array(im)[..., 3]
    os.makedirs('%s/art/characters/%s' % (R, fac), exist_ok=True)
    os.makedirs('%s/assets/characters/%s' % (R, fac), exist_ok=True)
    master = '%s/art/characters/%s/%s.webp' % (R, fac, name)
    im.save(master, quality=94, method=6)
    if kind == 'full_body':
        g = im.resize((im.width // 2, im.height // 2), Image.LANCZOS); game = '%s/assets/characters/%s/%s_full.webp' % (R, fac, cid)
    else:
        g = im.resize((512, 512), Image.LANCZOS); game = '%s/assets/characters/%s/%s_portrait.webp' % (R, fac, cid)
    g.save(game, quality=90, method=6)
    edge = {'top': int((a[0] > 128).sum()), 'bottom': int((a[-1] > 128).sum()), 'left': int((a[:, 0] > 128).sum()), 'right': int((a[:, -1] > 128).sum())}
    ys, xs = np.nonzero(a > 128)
    left = int((a > 200).sum() * 0 + ((np.array(Image.open(src).convert('RGB')).astype(int)[..., 1] - np.maximum(np.array(Image.open(src).convert('RGB')).astype(int)[..., 0], np.array(Image.open(src).convert('RGB')).astype(int)[..., 2]) > 150) & (a > 200)).sum())
    return {'id': cid, 'faction': fac, 'kind': kind, 'src': src, 'size': list(Image.open(src).size), 'master': master[len(R) + 1:], 'game': game[len(R) + 1:],
            'bbox': [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())], 'edge': edge, 'green_left': left}
if __name__ == '__main__':
    fs = sorted(glob.glob(os.path.join(sys.argv[1] if len(sys.argv) > 1 else 'chars_src', '*/*.png')))
    with Pool(8) as p: res = p.map(one, fs)
    json.dump(res, open(os.path.join(R, 'art/characters/process.json'), 'w'), indent=1)
    for r in res:
        e = r['edge']; clip = [k for k, v in e.items() if v > 3 and not (r['kind'] == 'thigh_up_square' and k == 'bottom')]
        if clip or r['green_left'] > 200: print(r['id'], r['kind'], 'touches', clip, e, 'green left', r['green_left'])
    print(len(res), 'done')
