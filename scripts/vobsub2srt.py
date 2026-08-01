#!/usr/bin/env python3
"""
vobsub2srt.py — Decode VobSub (.sub/.idx) to SRT using tesseract OCR.
Usage: python3 vobsub2srt.py <input.idx> <lang_3letter> [output.srt]
"""
import sys, os, re, struct
import pytesseract
from PIL import Image, ImageFilter, ImageOps

TESS_MAP = {
    'eng':'eng','fre':'fra','fra':'fra','spa':'spa','por':'por',
    'ger':'deu','deu':'deu','ita':'ita','jpn':'jpn','chi':'chi_sim',
    'zho':'chi_sim','rus':'rus','kor':'kor','nld':'nld','dut':'nld',
}

def ms_to_srt(ms):
    h=ms//3600000; ms%=3600000; m=ms//60000; ms%=60000
    s=ms//1000; ms%=1000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def parse_idx(idx_path):
    entries=[]; palette=[]
    with open(idx_path,'r',encoding='latin-1') as f:
        for line in f:
            m=re.match(r'timestamp:\s*(\d+):(\d+):(\d+):(\d+),\s*filepos:\s*([0-9a-fA-F]+)',line)
            if m:
                h,mn,s,ms=int(m.group(1)),int(m.group(2)),int(m.group(3)),int(m.group(4))
                entries.append(((h*3600+mn*60+s)*1000+ms, int(m.group(5),16)))
            pm=re.match(r'palette:\s*(.+)',line)
            if pm:
                palette=[int(x.strip(),16) for x in pm.group(1).split(',')]
    return entries, palette

def read_dvdsub_packet(data, offset):
    pos=offset; payload=bytearray()
    while pos<len(data)-6:
        if data[pos:pos+3]!=b'\x00\x00\x01': break
        pid=data[pos+3]
        if pid==0xBA:
            stuffing=data[pos+13]&0x07; pos+=14+stuffing; continue
        if pid!=0xBD: break
        pkt_len=struct.unpack('>H',data[pos+4:pos+6])[0]
        hdr_data_len=data[pos+8]
        sub_start=pos+9+hdr_data_len
        data_start=sub_start+1; data_end=pos+6+pkt_len
        payload.extend(data[data_start:data_end])
        pos=data_end
        if len(payload)>=4 and len(payload)>=struct.unpack('>H',payload[0:2])[0]: break
    return bytes(payload)

def palette_entry_to_rgba(color_int, alpha):
    """Convert palette entry to RGBA. Auto-detects RGB vs YCbCr format."""
    r=(color_int>>16)&0xFF; g=(color_int>>8)&0xFF; b=color_int&0xFF
    return (r,g,b,alpha)

def palette_entry_to_rgba_ycbcr(color_int, alpha):
    y=(color_int>>16)&0xFF; cb=(color_int>>8)&0xFF; cr=color_int&0xFF
    r=max(0,min(255,int(y+1.402*(cr-128))))
    g=max(0,min(255,int(y-0.344*(cb-128)-0.714*(cr-128))))
    b=max(0,min(255,int(y+1.772*(cb-128))))
    return (r,g,b,alpha)

def detect_palette_format(palette):
    for entry in palette:
        r,g,b = (entry>>16)&0xFF, (entry>>8)&0xFF, entry&0xFF
        ry,gy,by = palette_entry_to_rgba_ycbcr(entry, 0)[:3]
        if gy > ry+50 and gy > by+50:
            return 'rgb'
    return 'ycbcr'

def decode_rle(data, nib_start, max_nibs, width):
    def nib(p):
        if p//2>=len(data): return 0
        b=data[p//2]; return (b>>4)&0xF if p%2==0 else b&0xF
    pixels=[]; pos=nib_start
    while len(pixels)<width and pos<max_nibs:
        n=nib(pos); pos+=1
        if n>=4: count=n>>2; color=n&3
        else:
            n=(n<<4)|nib(pos); pos+=1
            if n>=16: count=n>>2; color=n&3
            else:
                n=(n<<4)|nib(pos); pos+=1
                if n>=64: count=n>>2; color=n&3
                else:
                    n=(n<<4)|nib(pos); pos+=1
                    count=n>>2 if n>=4 else (width-len(pixels)); color=n&3
        pixels.extend([color]*min(count,width-len(pixels)))
    if pos%2!=0: pos+=1
    return pixels, pos

def decode_frame(payload, palette_raw, palette_format='ycbcr'):
    """Decode one DVD subtitle packet to a PIL Image."""
    if len(payload)<4: return None
    ctrl_off=struct.unpack('>H',payload[2:4])[0]
    if ctrl_off>=len(payload): return None

    # Parse control sequence (date(2)+next_ptr(2)+commands)
    pos=ctrl_off+4
    colors={3:0,2:1,1:2,0:3}; alphas={3:255,2:255,1:255,0:0}
    area=None; f1=None; f2=None

    while pos<len(payload):
        cmd=payload[pos]; pos+=1
        if cmd in (0x00,0x01,0x02): pass
        elif cmd==0x03:
            if pos+1<len(payload):
                b1,b2=payload[pos],payload[pos+1]; pos+=2
                colors[3]=(b1>>4)&0xF; colors[2]=b1&0xF
                colors[1]=(b2>>4)&0xF; colors[0]=b2&0xF
        elif cmd==0x04:
            if pos+1<len(payload):
                b1,b2=payload[pos],payload[pos+1]; pos+=2
                alphas[3]=((b1>>4)&0xF)*17; alphas[2]=(b1&0xF)*17
                alphas[1]=((b2>>4)&0xF)*17; alphas[0]=(b2&0xF)*17
        elif cmd==0x05:
            if pos+5<len(payload):
                x1=((payload[pos]<<4)|(payload[pos+1]>>4))
                x2=(((payload[pos+1]&0xF)<<8)|payload[pos+2])
                y1=((payload[pos+3]<<4)|(payload[pos+4]>>4))
                y2=(((payload[pos+4]&0xF)<<8)|payload[pos+5])
                area=(x1,y1,x2,y2); pos+=6
        elif cmd==0x06:
            if pos+3<len(payload):
                f1=struct.unpack('>H',payload[pos:pos+2])[0]; pos+=2
                f2=struct.unpack('>H',payload[pos:pos+2])[0]; pos+=2
        elif cmd==0xFF: break
        else: pos+=1

    if area is None or f1 is None: return None
    x1,y1,x2,y2=area
    w=x2-x1+1; h=y2-y1+1
    if w<=0 or h<=0 or w>1920 or h>1080: return None

    color_map={}
    conv = palette_entry_to_rgba if palette_format == 'rgb' else palette_entry_to_rgba_ycbcr
    for i in range(4):
        pidx=colors[i]
        yuv=palette_raw[pidx] if pidx<len(palette_raw) else 0
        color_map[i]=conv(yuv, alphas[i])

    img=Image.new('RGBA',(w,h),(0,0,0,0))
    px=list(img.getdata())
    for field,start_y in [(f1,0),(f2,1)]:
        nib_pos=field*2; y=start_y
        while y<h:
            line,nib_pos=decode_rle(payload,nib_pos,len(payload)*2,w)
            for x,c in enumerate(line[:w]):
                if y<h: px[y*w+x]=color_map.get(c,(0,0,0,0))
            y+=2
    img.putdata(px)
    return img

def ocr_image(img, tess_lang):
    """Preprocess image and run tesseract OCR."""
    bbox=img.getbbox()
    if not bbox: return ""
    sub=img.crop(bbox)
    # Black background composite (white subtitle text on black → invert for tesseract)
    bg=Image.new('RGBA',sub.size,(0,0,0,255))
    bg.paste(sub,mask=sub.split()[3])
    gray=bg.convert('L')
    inv=ImageOps.invert(gray)
    big=inv.resize((inv.width*4,inv.height*4),Image.LANCZOS)
    big=big.filter(ImageFilter.SHARPEN)
    return pytesseract.image_to_string(big,lang=tess_lang,config='--psm 6 --oem 1').strip()

def vobsub_to_srt(idx_path, lang3='eng', out_srt=None):
    tess_lang=TESS_MAP.get(lang3,'eng')
    sub_path=idx_path.replace('.idx','.sub')
    if not os.path.exists(sub_path):
        print(f"ERROR: {sub_path} not found",file=sys.stderr); return 0

    entries,palette=parse_idx(idx_path)
    if not entries:
        print("ERROR: No entries in .idx",file=sys.stderr); return 0

    palette_fmt = detect_palette_format(palette)

    if out_srt is None:
        out_srt=idx_path.replace('.idx',f'.{lang3}.srt')

    with open(sub_path,'rb') as f:
        sub_data=f.read()

    print(f"  {len(entries)} frames | OCR lang: {tess_lang}")
    srt_entries=[]

    for i,(start_ms,offset) in enumerate(entries):
        end_ms=entries[i+1][0] if i+1<len(entries) else start_ms+4000
        try:
            payload=read_dvdsub_packet(sub_data,offset)
            if not payload: continue
            img=decode_frame(payload,palette,palette_fmt)
            if img is None: continue
            text=ocr_image(img,tess_lang)
            if text:
                # Clean up common OCR artifacts
                text=re.sub(r'[|¦]','I',text)
                text=text.strip()
                srt_entries.append((start_ms,end_ms,text))
        except Exception:
            pass
        if (i+1)%200==0:
            pct=(i+1)*100//len(entries)
            print(f"  {pct}% ({i+1}/{len(entries)}, {len(srt_entries)} subs so far)")

    with open(out_srt,'w',encoding='utf-8') as f:
        for idx,(start,end,text) in enumerate(srt_entries,1):
            f.write(f"{idx}\n{ms_to_srt(start)} --> {ms_to_srt(end)}\n{text}\n\n")

    print(f"  ✓ {len(srt_entries)} subtitles → {out_srt}")
    return len(srt_entries)

if __name__=='__main__':
    if len(sys.argv)<3:
        print(f"Usage: {sys.argv[0]} <input.idx> <lang_3letter> [output.srt]"); sys.exit(1)
    vobsub_to_srt(sys.argv[1],sys.argv[2],sys.argv[3] if len(sys.argv)>3 else None)
