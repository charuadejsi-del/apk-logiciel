from PIL import Image, ImageDraw, ImageFilter
import math
S=1024; GOLD=(212,175,55,255); GOLD2=(240,210,120,255)
def emblem(d, cx, cy, r, w):
    # étoile à 8 branches (Rub el Hizb) : deux carrés tournés
    for ang in (0,45):
        pts=[(cx+r*math.cos(math.radians(ang+45+90*i)), cy+r*math.sin(math.radians(ang+45+90*i))) for i in range(4)]
        d.line(pts+[pts[0]], fill=GOLD, width=w, joint='curve')
    # livre ouvert
    bw=r*0.62; bh=r*0.42; top=cy-bh*0.35
    left=[(cx,top+bh*0.12),(cx-bw,top),(cx-bw,top+bh),(cx,top+bh+bh*0.12)]
    right=[(cx,top+bh*0.12),(cx+bw,top),(cx+bw,top+bh),(cx,top+bh+bh*0.12)]
    d.polygon(left, fill=GOLD2); d.polygon(right, fill=GOLD)
    d.line([(cx,top+bh*0.12),(cx,top+bh*1.12)], fill=(11,61,46,255), width=max(4,w//2))
    for k in range(1,4):  # lignes de texte
        y=top+bh*k/4
        d.line([(cx-bw*0.85,y-bh*0.03*k/3),(cx-bw*0.15,y+bh*0.08)], fill=(11,61,46,200), width=max(3,w//4))
        d.line([(cx+bw*0.15,y+bh*0.08),(cx+bw*0.85,y-bh*0.03*k/3)], fill=(11,61,46,200), width=max(3,w//4))
def bg():
    im=Image.new('RGBA',(S,S)); px=im.load()
    for y in range(S):
        for x in range(S):
            t=math.hypot(x-S*0.35,y-S*0.3)/(S*1.1)
            px[x,y]=(int(20-12*t),int(95-45*t),int(68-30*t),255)
    m=Image.new('L',(S,S),0); ImageDraw.Draw(m).rounded_rectangle([0,0,S-1,S-1],radius=220,fill=255)
    out=Image.new('RGBA',(S,S),(0,0,0,0)); out.paste(im,(0,0),m); return out
full=bg(); d=ImageDraw.Draw(full); emblem(d,S/2,S/2,S*0.36,26)
full.save('icon.png')
fg=Image.new('RGBA',(S,S),(0,0,0,0)); emblem(ImageDraw.Draw(fg),S/2,S/2,S*0.25,20); fg.save('icon_fg.png')
small=full.resize((256,256),Image.LANCZOS); small.save('icon_256.png')
print('ok')
