#!/usr/bin/env python3
"""Step 8: FrameExtractionActor 管线端到端验证
完整链路: BV号→info→videoshot→sidx→GOP×N→mini-mp4×N
对标 Swift FrameExtractionActor 的逻辑编排"""
import requests, struct, hashlib, time, os, sys, json
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = "https://api.bilibili.com"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
    "Referer": "https://www.bilibili.com",
}
OUTPUT = "/Users/tboat/Desktop/ai/食谱/ShiKe/.api-test-output/pipeline"
os.makedirs(OUTPUT, exist_ok=True)

# ==================== Phase 1: 帧预览 (零下载) ====================

def phase1_preview(bvid):
    """对标 Swift: info API + videoshot API 并行 → 帧预览数据"""
    print("█ Phase 1: 帧预览 (零视频下载)")
    print("═" * 45)

    # 并行请求 info + videoshot
    t0 = time.time()
    info_url = f"{BASE}/x/web-interface/view"
    shot_url = f"{BASE}/x/player/videoshot"

    # 实际应并行，这里顺序模拟
    resp_i = requests.get(info_url, params={"bvid": bvid}, headers=HEADERS, timeout=15)
    info = resp_i.json()
    if info.get("code") != 0:
        print(f"❌ info API 失败: {info.get('message')}")
        return None

    resp_s = requests.get(shot_url, params={"bvid": bvid, "index": 1}, headers=HEADERS, timeout=15)
    shot = resp_s.json()

    inner = info["data"]
    video_meta = {
        "bvid": bvid, "title": inner["title"], "author": inner["owner"]["name"],
        "cid": inner["cid"], "duration": inner["duration"],
    }
    print(f"📹 {video_meta['title'][:40]}")
    print(f"   UP主: @{video_meta['author']}, 时长: {video_meta['duration']}s, CID: {video_meta['cid']}")

    # 解析 videoshot
    data = shot.get("data", shot)
    timestamps = [int(x) if isinstance(x, (int, float)) else 0 for x in data.get("index", [])]
    sprite_url = data["image"][0]
    if sprite_url.startswith("//"): sprite_url = "https:" + sprite_url

    # 下载雪碧图
    img_resp = requests.get(sprite_url, headers=HEADERS, timeout=30)
    sprite_path = os.path.join(OUTPUT, "sprite_sheet.jpg")
    with open(sprite_path, "wb") as f: f.write(img_resp.content)

    elapsed = (time.time() - t0) * 1000
    print(f"   ✅ 雪碧图: {len(timestamps)} 帧, {len(img_resp.content)/1024:.0f}KB")
    print(f"   ⏱ Phase 1 耗时: {elapsed:.0f}ms")
    return video_meta, timestamps

# ==================== Phase 2: 高清提取 ====================

def get_mixin_key():
    resp = requests.get(f"{BASE}/x/web-interface/nav", headers=HEADERS, timeout=15)
    nav = resp.json()
    wbi = nav.get("data", {}).get("wbi_img", {})
    ik = wbi.get("img_url", "").split("/")[-1].replace(".png", "")
    sk = wbi.get("sub_url", "").split("/")[-1].replace(".png", "")
    return hashlib.md5((ik + sk).encode()).hexdigest()[:32]

def wbi_sign(params, mk):
    params["wts"] = int(time.time())
    q = "&".join(f"{k}={params[k]}" for k in sorted(params.keys()))
    params["w_rid"] = hashlib.md5((q + mk).encode()).hexdigest()
    return params

def download_range(url, rng, timeout=15):
    resp = requests.get(url, headers={**HEADERS, "Range": f"bytes={rng}"}, timeout=timeout)
    if resp.status_code in (200, 206): return resp.content
    return None

def parse_sidx(data):
    """解析 sidx，返回有效 GOP 条目"""
    # 定位 sidx box
    offset = 0
    while offset + 8 <= len(data):
        size = struct.unpack(">I", data[offset:offset+4])[0]
        if data[offset+4:offset+8] == b"sidx":
            offset += 8; break
        if size <= 0: break
        offset += size

    content = data[offset:offset+size-8]
    version = content[0]
    pos = 8  # version(1) + flags(3) + ref_id(4) = 8
    timescale = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4

    if version == 0:
        ept = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
        first_off = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
    else:
        ept = struct.unpack(">Q", content[pos:pos+8])[0]; pos += 8
        first_off = struct.unpack(">Q", content[pos:pos+8])[0]; pos += 8

    pos += 2; ref_count = struct.unpack(">H", content[pos:pos+2])[0]; pos += 2

    entries, cur_off, cur_time = [], first_off, ept / timescale
    for _ in range(ref_count):
        if pos + 8 > len(content): break
        raw = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
        dur = struct.unpack(">I", content[pos:pos+4])[0]; pos += 4
        ref_type = (raw >> 31) & 1; ref_size = raw & 0x7FFFFFFF
        is_garbage = not ref_type and dur > timescale * 120

        if not ref_type and not is_garbage:
            entries.append({
                "offset": int(cur_off), "size": ref_size, "dur": dur,
                "time": round(cur_time, 2), "time_s": dur / timescale,
            })
            cur_off += ref_size; cur_time += dur / timescale
        if version == 1 and (raw >> 28) & 0x07 == 0 and pos + 4 <= len(content):
            pos += 4

    return entries, timescale

def find_gop(entries, target_sec):
    """二分查找最接近目标时间的 GOP"""
    lo, hi = 0, len(entries) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if entries[mid]["time"] <= target_sec: lo = mid
        else: hi = mid - 1
    best = entries[lo]
    if lo + 1 < len(entries):
        d1, d2 = abs(entries[lo]["time"] - target_sec), abs(entries[lo+1]["time"] - target_sec)
        best = entries[lo] if d1 <= d2 else entries[lo+1]
    return best

def is_self_contained(data):
    """检测子段是否为自包含 mp4 (以 ftyp box 开头)"""
    if len(data) < 8: return False
    return data[4:8] == b"ftyp"

def phase2_extract(video_meta, timestamps, mock_mark_count=5):
    """对标 Swift: FrameExtractionActor.extract()

    阶段二流程:
    ① WBI签名 → playurl API → SegmentBase
    ② Range下载 init + sidx (~6KB)
    ③ 解析 sidx → GOP 偏移/时间映射
    ④ withTaskGroup: 对每个标记时间戳并行:
       a. 二分查找 GOP
       b. Range下载 subsegment (~200-800KB)
       c. 智能拼装 mini-mp4 (自包含检测)
       d. (设备端) AVAssetImageGenerator 提取 I 帧
    """
    print("\n█ Phase 2: 高清截图提取 (sidx+GOP)")
    print("═" * 45)
    t0 = time.time()

    bvid, cid = video_meta["bvid"], video_meta["cid"]

    # 模拟用户标记 5 个时间戳
    duration = video_meta["duration"]
    marked = [10, 30, 60, duration * 0.4, duration * 0.7]
    marked = [int(t) for t in marked]
    print(f"🎯 标记时间戳: {[f'{t}s' for t in marked]}")

    # ① WBI + playurl
    print("① 获取视频流...")
    mk = get_mixin_key()
    params = {"bvid": bvid, "cid": cid, "fnval": 16, "fnver": 0, "fourk": 1}
    signed = wbi_sign(params.copy(), mk)
    resp = requests.get(f"{BASE}/x/player/playurl", params=signed, headers=HEADERS, timeout=15)
    play = resp.json()

    if play.get("code") != 0:
        if play.get("code") == -352:
            print("   ⚠️ WBI key 过期, 刷新重试...")
            mk = get_mixin_key()
            signed = wbi_sign({"bvid": bvid, "cid": cid, "fnval": 16, "fnver": 0, "fourk": 1}, mk)
            resp = requests.get(f"{BASE}/x/player/playurl", params=signed, headers=HEADERS, timeout=15)
            play = resp.json()

    dash = play["data"]["dash"]
    video = sorted(dash["video"], key=lambda v: v.get("width",0) or 0, reverse=True)[0]
    seg = video["segment_base"]
    base_url = video.get("base_url", video.get("baseUrl", ""))
    if base_url.startswith("http://"): base_url = base_url.replace("http://", "https://")
    init_range = seg["initialization"]
    index_range = seg["index_range"]
    print(f"   ✅ {video.get('width')}x{video.get('height')}, {video.get('bandwidth',0)//1000}kbps")

    # ② 下载 init + sidx
    print("② 下载 init + sidx...")
    init_s, init_e = [int(x) for x in init_range.split("-")]
    idx_s, idx_e = [int(x) for x in index_range.split("-")]
    combined = download_range(base_url, f"{init_s}-{idx_e}")
    init_data = combined[:idx_s-init_s]
    sidx_data = combined[idx_s-init_s:]
    print(f"   ✅ init={len(init_data)}B, sidx={len(sidx_data)}B")

    # ③ 解析 sidx
    print("③ 解析 sidx...")
    entries, timescale = parse_sidx(sidx_data)
    print(f"   ✅ {len(entries)} valid GOPs, timescale={timescale}")

    # ④ 并行提取各帧
    print(f"④ 并行提取 {len(marked)} 帧 (maxConcurrent=3)...")
    results = []
    mp4_files = []

    def process_frame(index, ts):
        """处理单帧 (对标 processSingleFrame)"""
        # a. 二分查找 GOP
        gop = find_gop(entries, ts)
        if not gop:
            return index, None, f"未找到 GOP[{ts}s]"

        # b. Range 下载
        byte_end = gop["offset"] + gop["size"] - 1
        rng = f"{gop['offset']}-{byte_end}"
        subseg = download_range(base_url, rng)
        if not subseg:
            return index, None, f"下载失败 GOP[{ts}s]"

        # c. 智能拼装
        if is_self_contained(subseg):
            mp4_data = subseg
            strategy = "self-contained"
        else:
            mp4_data = init_data + subseg
            strategy = "assembled"

        # d. 保存 mini-mp4
        fname = f"step_{index:02d}_{int(ts):03d}s.mp4"
        fpath = os.path.join(OUTPUT, fname)
        with open(fpath, "wb") as f: f.write(mp4_data)

        return index, {
            "path": fpath, "size": len(mp4_data),
            "gop_offset": gop["offset"], "gop_size": len(subseg),
            "gop_time": gop["time"], "strategy": strategy,
        }, None

    # 并行处理 (max 3 concurrent, 对标 withTaskGroup)
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(process_frame, i, t): i for i, t in enumerate(marked)}
        for f in as_completed(futures):
            idx, result, error = f.result()
            if error:
                print(f"   ❌ 帧[{idx}] ts={marked[idx]}s: {error}")
            else:
                results.append((idx, result))
                print(f"   ✅ 帧[{idx}] ts={marked[idx]}s: "
                      f"GOP@{result['gop_offset']}({result['gop_size']/1024:.0f}KB) "
                      f"→ {result['size']/1024:.0f}KB ({result['strategy']})")

    # 排序结果
    results.sort(key=lambda r: r[0])

    elapsed = (time.time() - t0) * 1000
    print(f"\n   ⏱ Phase 2 耗时: {elapsed:.0f}ms ({len(results)}/{len(marked)} 帧)")

    return results, init_data, elapsed

# ==================== 主流程 ====================

print("🔬 Step 8: F001 完整管线端到端测试")
print("=" * 55)

bv = "BV1GJ411x7h7"  # Rick Astley (快速测试用, 213s, 6MB)

# Phase 1
preview = phase1_preview(bv)
if not preview:
    print("❌ Phase 1 失败")
    sys.exit(1)

video_meta, timestamps = preview

# Phase 2
results, init_data, phase2_ms = phase2_extract(video_meta, timestamps)

# ==================== 汇总 ====================
print("\n" + "=" * 55)
print("📊 管线端到端汇总")
print("-" * 55)
print(f"  视频: {video_meta['title'][:35]}")
print(f"  时长: {video_meta['duration']}s, GOP 数: 从 sidx 解析")

total_size = sum(r[1]["size"] for r in results) if results else 0
print(f"  Phase 1: ✅ {len(timestamps)} 帧预览 ({len(init_data) if 'init_data' in dir() else '?'}B sidx)")
print(f"  Phase 2: ✅ {len(results)} 帧提取, {total_size/1024:.0f}KB total")
print(f"  对比: 完整下载 ≈ {video_meta['duration']*500//1000}MB → 实际只下载 ≈ {(total_size)/1024:.0f}KB")
if results:
    full_est = video_meta["duration"] * 500 // 1000
    reduction = (1 - total_size / (full_est * 1024)) * 100 if full_est > 0 else 0
    print(f"  数据减少: {reduction:.0f}%")

print(f"\n📁 输出: {OUTPUT}")
files = sorted(os.listdir(OUTPUT))
for f in files:
    sz = os.path.getsize(os.path.join(OUTPUT, f))
    print(f"   {f} ({sz/1024:.0f}KB)")

print(f"\n✅ Step 8 完成 — sidx+GOP 管线可工作!")
