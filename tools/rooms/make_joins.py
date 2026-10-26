"""Make the owner's "join image" for a split room picture (front view on top, back view below): each row keeps 560 px
of the two views that meet at a join, with a white gap between them for ChatGPT to paint.
Row 1: right end of FRONT | gap | left end of BACK.  Row 2: right end of BACK | gap | left end of FRONT.
usage: python3 tools/rooms/make_joins.py split.png out_joins.png"""
import sys
from PIL import Image
E = 560
im = Image.open(sys.argv[1]).convert("RGB"); W, H = im.size; m = H // 2
top = im.crop((0, 0, W, m - 6)); bot = im.crop((0, m + 6, W, H)); h = min(top.height, bot.height)
top = top.crop((0, 0, W, h)); bot = bot.crop((0, 0, W, h))
out = Image.new("RGB", (W, H), "white")
out.paste(top.crop((W - E, 0, W, h)), (0, 0)); out.paste(bot.crop((0, 0, E, h)), (W - E, 0))
out.paste(bot.crop((W - E, 0, W, h)), (0, H - h)); out.paste(top.crop((0, 0, E, h)), (W - E, H - h))
out.save(sys.argv[2])
