#!/usr/bin/env python3
"""Step 6+7: GOP 下载 + mini-mp4 拼装 + I 帧提取验证"""
import requests
import struct
import hashlib
import time
import os
import sys

BASE = "https://api.bilibili.com"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
    "Referer": "https://www.bilibili.com",
}
OUTPUT = "/Users/tboat/Desktop/ai/食谱/ShiKe/.api-test-output/gop_test"
os.makedirs(OUTPUT, exist_ok=True)

def hex_dump(data, max_len=64):
    return data[:max_len].hex(' ')

def box_name(typ):
    try: return typ.decode('ascii')
    except: return str(typ)

# ==================== 复用 Step 4+5 逻辑 ====================

def get_mixin_key():
    resp = requests.get(f"{BASE}/x/web-interface/nav", headers=HEADERS, timeout=15)
    nav = resp.json()
    wbi_img = nav.get("data", {}).get("wbi_img", {})
    img_key = wbi_img.get("img_url", "").split("/")[-1].replace(".png", "")
    sub_key = wbi_img.get("sub_url", "").split("/")[-1].replace(".png", "")
    return hashlib.md5((img_key + sub_key).encode()).hexdigest()[:32]

def wbi_sign(params, mixin_key):
    params["wts"] = int(time.time())
    query = "&".join(f"{k}={params[k]}" for k in sorted(params.keys()))
    params["w_rid"] = hashlib.md5((query + mixin_key).encode()).hexdigest()
    return params

def get_playurl(bvid, cid, mixin_key):
    params = {"bvid": bvid, "cid": cid, "fnval": 16, "fnver": 0, "fourk": 1}
    signed = wbi_sign(params.copy(), mixin_key)
    resp = requests.get(f"{BASE}/x/player/playurl", params=signed, headers=HEADERS, timeout=15)
    data = resp.json()
    if data.get("code") != 0:
        return None
    dash = data["data"]["dash"]
    video = sorted(dash["video"], key=lambda v: v.get("width", 0) or 0, reverse=True)[0]
    seg = video.get("segment_base", {})
    base_url = video.get("base_url", video.get("baseUrl", ""))
    if base_url.startswith("http://"):
        base_url = base_url.replace("http://", "https://")
    return {
        "init_range": seg["initialization"],
        "index_range": seg["index_range"],
        "base_url": base_url,
        "width": video.get("width"),
        "height": video.get("height"),
        "codecs": video.get("codecs"),
        "bandwidth": video.get("bandwidth"),
    }

def download_init_sidx(playurl):
    """下载 init + sidx"""
    base_url = playurl["base_url"]
    init_s, init_e = [int(x) for x in playurl["init_range"].split("-")]
    idx_s, idx_e = [int(x) for x in playurl["index_range"].split("-")]
    rng = f"bytes={init_s}-{idx_e}"
    resp = requests.get(base_url, headers={**HEADERS, "Range": rng}, timeout=30)
    if resp.status_code not in (200, 206):
        return None, None
    data = resp.content
    init_len = idx_s - init_s
    return data[:init_len], data[init_len:]

def parse_sidx(sidx_data):
    """解析 sidx，返回有效 GOP 条目列表"""
    # Find sidx box
    offset = 0
    while offset + 8 <= len(sidx_data):
        size = struct.unpack(">I", sidx_data[offset:offset+4])[0]
        typ = sidx_data[offset+4:offset+8]
        if typ == b"sidx":
            offset += 8
            break
        if size <= 0: break
        offset += size

    content = sidx_data[offset:offset+size-8]
    version = content[0]
    pos = 1 + 3 + 4  # version + flags + ref_id
    timescale = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4

    if version == 0:
        ept = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
        first_off = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
    else:
        ept = struct.unpack(">Q", content[pos:pos+8])[0]; pos += 8
        first_off = struct.unpack(">Q", content[pos:pos+8])[0]; pos += 8

    pos += 2
    ref_count = struct.unpack(">H", content[pos:pos+2])[0]; pos += 2

    entries = []
    cur_off = first_off
    cur_time = ept / timescale

    for _ in range(ref_count):
        if pos + 8 > len(content): break
        raw = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
        dur = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
        ref_type = (raw >> 31) & 1
        ref_size = raw & 0x7FFFFFFF
        # 过滤层级引用和明显垃圾数据
        is_hierarchical = ref_type == 1
        is_garbage = not is_hierarchical and dur > timescale * 120  # >2min 肯定不对

        if not is_hierarchical and not is_garbage:
            entries.append({
                "offset": cur_off, "size": ref_size,
                "dur": dur, "time": round(cur_time, 2),
                "time_s": dur / timescale,
            })
            # ✅ 仅对有效条目累积 offset 和时间
            cur_off += ref_size
            cur_time += dur / timescale
        # hierarchical/garbage 条目不累积 offset（它们不代表实际媒体数据）

        if version == 1 and (raw >> 28) & 0x07 == 0 and pos + 4 <= len(content):
            pos += 4

    return entries, timescale

# ==================== Step 6: GOP 下载 + 拼装 ====================

def download_gop(base_url, entry):
    """下载单个 GOP subsegment"""
    byte_start = entry["offset"]
    byte_end = byte_start + entry["size"] - 1
    rng = f"bytes={byte_start}-{byte_end}"

    t0 = time.time()
    resp = requests.get(base_url, headers={**HEADERS, "Range": rng}, timeout=15)
    elapsed = (time.time() - t0) * 1000

    if resp.status_code not in (200, 206):
        return None, elapsed, resp.status_code

    return resp.content, elapsed, resp.status_code

def assemble_mp4(init_data, gop_data, index):
    """拼装 init + subsegment → mini-mp4"""
    mp4 = init_data + gop_data
    path = os.path.join(OUTPUT, f"mini_t{index:02d}.mp4")
    with open(path, "wb") as f:
        f.write(mp4)
    return path, len(mp4)

def validate_mp4(path):
    """验证 mini-mp4 内部的 box 结构"""
    with open(path, "rb") as f:
        data = f.read()

    boxes = []
    offset = 0
    while offset + 8 <= len(data):
        size = struct.unpack(">I", data[offset:offset+4])[0]
        # size=1 表示 extended size (64-bit)，实际用 size=0 判断不够
        # mdat box 经常 size=0 表示"延伸到文件末尾"
        if size == 0:
            # extends to end of file
            typ = data[offset+4:offset+8]
            actual_size = len(data) - offset
            boxes.append((offset, actual_size, box_name(typ)))
            break
        if size == 1:
            # 64-bit extended size
            size = struct.unpack(">Q", data[offset+8:offset+16])[0]
        if size < 8 or offset + size > len(data):
            break
        typ = data[offset+4:offset+8]
        boxes.append((offset, size, box_name(typ)))
        offset += size

    types = [b[2] for b in boxes]
    return {
        "valid": "moof" in types and "mdat" in types,
        "boxes": boxes,
        "has_ftyp": "ftyp" in types,
        "has_moov": "moov" in types,
        "has_moof": "moof" in types,
        "has_mdat": "mdat" in types,
        "total_size": len(data),
    }

# ==================== Step 7: I 帧提取预览 ====================

def extract_iframe_preview(mp4_path, output_path):
    """尝试用 ffmpeg 提取第一帧作为预览"""
    import subprocess
    try:
        result = subprocess.run(
            ["ffmpeg", "-y", "-i", mp4_path, "-vframes", "1",
             "-f", "image2", output_path],
            capture_output=True, text=True, timeout=10
        )
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            return True, "ffmpeg"
    except FileNotFoundError:
        pass
    except Exception as e:
        pass

    # Fallback: 用 PIL 读取 mp4 第一帧
    try:
        from PIL import Image
        import io
        # 对于 mini-mp4，PIL 可能不支持直接读取
        # 尝试用 imageio 或其他方式
    except ImportError:
        pass

    return False, "no tool available"

# ==================== 主流程 ====================

print("🔬 Step 6+7: GOP 下载 + mini-mp4 拼装")
print("=" * 50)

# 选择测试视频（用信息密度更高的）
bv_list = ["BV1GJ411x7h7", "BV1xx411c7mD"]  # Rick Astley, 测试视频
bv = bv_list[0]

# 获取 CID
resp = requests.get(f"{BASE}/x/web-interface/view", params={"bvid": bv}, headers=HEADERS, timeout=15)
info = resp.json()
if info.get("code") != 0:
    # fallback
    resp = requests.get(f"{BASE}/x/web-interface/view", params={"bvid": bv_list[1]}, headers=HEADERS, timeout=15)
    info = resp.json()
    bv = bv_list[1]

inner = info["data"]
cid = inner["cid"]
print(f"📹 {inner['title'][:40]} (CID={cid}, {inner['duration']}s)")

# 获取 WBI
mixin_key = get_mixin_key()
print(f"✅ WBI mixin_key: {mixin_key[:8]}...")

# 获取 playurl
playurl = get_playurl(bv, cid, mixin_key)
if not playurl:
    print("❌ playurl 获取失败")
    sys.exit(1)
print(f"✅ playurl: {playurl['width']}x{playurl['height']}, {playurl.get('bandwidth', 0)//1000}kbps, {playurl['codecs']}")

# 下载 init + sidx
init_data, sidx_data = download_init_sidx(playurl)
if init_data is None:
    print("❌ init+sidx 下载失败")
    sys.exit(1)
print(f"✅ init: {len(init_data)} bytes, sidx: {len(sidx_data)} bytes")

# 保存 init
with open(os.path.join(OUTPUT, "init_segment.bin"), "wb") as f:
    f.write(init_data)

# 解析 sidx
entries, timescale = parse_sidx(sidx_data)
print(f"✅ sidx: {len(entries)} valid GOPs, timescale={timescale}")

# 显示前 5 个 GOP
print(f"\n📋 GOP entries (first 5):")
print(f"   {'idx':>4} {'offset':>10} {'size(KB)':>10} {'time(s)':>9} {'dur(s)':>8}")
for i, e in enumerate(entries[:5]):
    print(f"   {i:>4} {e['offset']:>10} {e['size']/1024:>9.1f} {e['time']:>9.2f} {e['time_s']:>7.1f}s")

# ===== Step 6: 下载 3 个 GOP 并拼装 =====
print(f"\n{'='*50}")
print("Step 6: GOP 下载 + mini-mp4 拼装")

base_url = playurl["base_url"]
results = []

for i in range(min(3, len(entries))):
    entry = entries[i]
    print(f"\n--- GOP[{i}] ---")
    print(f"   offset={entry['offset']}, size={entry['size']} ({entry['size']/1024:.1f}KB), time={entry['time']}s")

    # 下载
    gop_data, elapsed, status = download_gop(base_url, entry)
    if gop_data is None:
        print(f"   ❌ 下载失败: HTTP {status}")
        continue
    print(f"   ✅ 下载: {len(gop_data)} bytes in {elapsed:.0f}ms (HTTP {status})")

    # 拼装
    mp4_path, mp4_size = assemble_mp4(init_data, gop_data, i)
    print(f"   ✅ 拼装: {mp4_path} ({mp4_size/1024:.1f}KB)")

    # 验证 mp4 结构
    validation = validate_mp4(mp4_path)
    status_icon = "✅" if validation["valid"] else "❌"
    print(f"   {status_icon} 验证: ftyp={validation['has_ftyp']}, moov={validation['has_moov']}, "
          f"moof={validation['has_moof']}, mdat={validation['has_mdat']}")

    results.append({
        "index": i,
        "mp4_path": mp4_path,
        "gop_size": len(gop_data),
        "mp4_size": mp4_size,
        "validation": validation,
        "entry": entry,
    })

    if i < 2:
        time.sleep(0.5)  # 避免请求过快

# ===== Step 7: I 帧提取尝试 =====
print(f"\n{'='*50}")
print("Step 7: I 帧提取验证")

for r in results:
    preview_path = r["mp4_path"].replace(".mp4", "_preview.jpg")
    ok, tool = extract_iframe_preview(r["mp4_path"], preview_path)
    if ok:
        size = os.path.getsize(preview_path)
        print(f"   ✅ GOP[{r['index']}]: 提取成功 → {preview_path} ({size/1024:.0f}KB, via {tool})")
    else:
        print(f"   ⚠️ GOP[{r['index']}]: 提取工具不可用 ({tool})")

# ===== 汇总 =====
print(f"\n{'='*50}")
print("📊 Step 6+7 汇总")
print("-" * 50)

total_gop = sum(r["gop_size"] for r in results)
total_mp4 = sum(r["mp4_size"] for r in results)
valid_count = sum(1 for r in results if r["validation"]["valid"])

print(f"  GOP 下载:   {len(results)}/{min(3, len(entries))} 成功")
print(f"  总 GOP 大小: {total_gop/1024:.0f}KB")
print(f"  总 mp4 大小: {total_mp4/1024:.0f}KB")
print(f"  mp4 结构:   {valid_count}/{len(results)} 有效")

if results:
    avg_gop = total_gop / len(results) / 1024
    print(f"  平均 GOP:   {avg_gop:.0f}KB")
    print(f"  数据量对比:  init+sidx={len(init_data)+len(sidx_data)} bytes + {len(results)}×GOP={total_gop/1024:.0f}KB ≈ {(len(init_data)+len(sidx_data)+total_gop)/1024:.0f}KB total")
    print(f"  完整视频:   ~{inner['duration']*playurl.get('bandwidth',0)/8/1024/1024:.0f}MB")

print(f"\n📁 输出: {OUTPUT}")
print(f"   {' '.join(os.listdir(OUTPUT))}")
print(f"✅ Step 6+7 完成")
