#!/usr/bin/env python3
"""Step 4+5: WBI 签名 + playurl API + sidx box 下载解析"""
import requests
import json
import re
import struct
import hashlib
import time
import os

BASE = "https://api.bilibili.com"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
    "Referer": "https://www.bilibili.com",
}
OUTPUT = "/Users/tboat/Desktop/ai/食谱/ShiKe/.api-test-output"
os.makedirs(OUTPUT, exist_ok=True)

# 测试用 BV 号
# BV = "BV1GJ411x7h7"  # Rick Astley - 但 nav API 需要登录
BV = "BV1xx411c7mD"    # 备用测试

# ==================== WBI 签名 ====================

def get_mixin_key():
    """获取 WBI mixin_key
    nav API 即使未登录也会返回 wbi_img 数据 (code=-101, 无视)
    """
    print("\n" + "=" * 50)
    print("Step 4a: 获取 WBI mixin_key")

    # nav API: 未登录也会返回 wbi_img（code=-101 但 data 中仍有 keys）
    resp = requests.get(f"{BASE}/x/web-interface/nav", headers=HEADERS, timeout=15)
    nav = resp.json()

    # 即使 code != 0，也尝试提取 wbi_img
    wbi_img = nav.get("data", {}).get("wbi_img", {})
    img_url = wbi_img.get("img_url", "")
    sub_url = wbi_img.get("sub_url", "")

    if img_url and sub_url:
        img_key = img_url.split("/")[-1].replace(".png", "")
        sub_key = sub_url.split("/")[-1].replace(".png", "")
        mixin_key = hashlib.md5((img_key + sub_key).encode()).hexdigest()[:32]
        print(f"   ✅ img_key: {img_key}")
        print(f"   ✅ sub_key: {sub_key}")
        print(f"   ✅ mixin_key: {mixin_key}")
        print(f"   ℹ️  登录状态: {nav.get('message', 'N/A')}")
        return mixin_key

    print(f"   ❌ 无法提取 WBI keys")
    return None

def wbi_sign(params, mixin_key):
    """WBI 签名: 排序参数 → 拼接 → MD5(参数字符串+mixin_key) → w_rid"""
    params["wts"] = int(time.time())
    sorted_keys = sorted(params.keys())
    query = "&".join(f"{k}={params[k]}" for k in sorted_keys)
    params["w_rid"] = hashlib.md5((query + mixin_key).encode()).hexdigest()
    return params

# ==================== playurl API ====================

def test_playurl(bvid, cid, mixin_key):
    """测试 playurl API -> SegmentBase"""
    print("\n" + "=" * 50)
    print("Step 4b: playurl API (WBI 签名)")

    params = {"bvid": bvid, "cid": cid, "fnval": 16, "fnver": 0, "fourk": 1}
    signed = wbi_sign(params.copy(), mixin_key)

    url = f"{BASE}/x/player/playurl"
    resp = requests.get(url, params=signed, headers=HEADERS, timeout=15)
    data = resp.json()
    code = data.get("code")

    if code != 0:
        print(f"   ❌ playurl 失败: code={code}, msg={data.get('message')}")
        # 检查是否是 -352 (WBI key 过期)
        if code == -352:
            print(f"   ⚠️ WBI key 过期, 需要刷新")
        return None, code

    dash = data.get("data", {}).get("dash", {})
    videos = dash.get("video", [])
    if not videos:
        print("   ❌ 无 DASH 视频流")
        return None, code

    video = sorted(videos, key=lambda v: v.get("width", 0) or 0, reverse=True)[0]
    seg = video.get("segment_base", {})

    result = {
        "bvid": bvid, "cid": cid,
        "width": video.get("width"), "height": video.get("height"),
        "bandwidth": video.get("bandwidth"), "codecs": video.get("codecs"),
        "init_range": seg.get("initialization"),
        "index_range": seg.get("index_range"),
        "base_url": video.get("base_url", video.get("baseUrl", "")),
    }
    if result["base_url"].startswith("http://"):
        result["base_url"] = result["base_url"].replace("http://", "https://")

    print(f"   ✅ {result['width']}x{result['height']}, {result['bandwidth']//1000}kbps")
    print(f"   ✅ initRange: {result['init_range']}")
    print(f"   ✅ indexRange: {result['index_range']}")
    return result, code

# ==================== sidx ====================

def test_sidx(playurl_result):
    """下载 + 解析 sidx box"""
    print("\n" + "=" * 50)
    print("Step 5: sidx 下载 + 解析")

    base_url = playurl_result["base_url"]
    init_s, init_e = [int(x) for x in playurl_result["init_range"].split("-")]
    idx_s, idx_e = [int(x) for x in playurl_result["index_range"].split("-")]

    # Range 下载 init + sidx
    rng = f"bytes={init_s}-{idx_e}"
    print(f"   Range: {rng}")
    resp = requests.get(base_url, headers={**HEADERS, "Range": rng}, timeout=30)

    if resp.status_code not in (200, 206):
        print(f"   ❌ HTTP {resp.status_code}")
        return None

    data = resp.content
    init_len = idx_s - init_s
    sidx_data = data[init_len:]

    print(f"   ✅ 下载: {len(data)} bytes (init={init_len}, sidx={len(sidx_data)})")

    # 保存
    with open(os.path.join(OUTPUT, "init_segment.bin"), "wb") as f:
        f.write(data[:init_len])
    with open(os.path.join(OUTPUT, "sidx_box.bin"), "wb") as f:
        f.write(sidx_data)

    return parse_sidx(sidx_data)

def parse_sidx(data):
    """解析 sidx box"""
    # 定位 sidx box (跳过非目标 box)
    offset = 0
    while offset + 8 <= len(data):
        size = struct.unpack(">I", data[offset:offset+4])[0]
        box_type = data[offset+4:offset+8].decode("ascii", errors="ignore")
        if box_type == "sidx":
            offset += 8  # skip header, point to content
            break
        if size <= 0:
            break
        offset += size

    sidx = data[offset:]
    print(f"   ✅ sidx content: {len(sidx)} bytes")

    pos = 0
    version = sidx[pos]; pos += 1
    pos += 3  # flags
    pos += 4  # reference_id
    timescale = struct.unpack(">I", sidx[pos:pos+4])[0]; pos += 4

    if version == 0:
        ept = struct.unpack(">I", sidx[pos:pos+4])[0]; pos += 4
        first_offset = struct.unpack(">I", sidx[pos:pos+4])[0]; pos += 4
    else:
        ept = struct.unpack(">Q", sidx[pos:pos+8])[0]; pos += 8
        first_offset = struct.unpack(">Q", sidx[pos:pos+8])[0]; pos += 8

    pos += 2  # reserved
    ref_count = struct.unpack(">H", sidx[pos:pos+2])[0]; pos += 2

    print(f"   v={version}, timescale={timescale}, entries={ref_count}")

    entries = []
    cur_off = first_offset
    cur_time = ept / timescale

    for i in range(ref_count):
        if pos + 8 > len(sidx):
            break
        raw = struct.unpack(">I", sidx[pos:pos+4])[0]; pos += 4
        dur = struct.unpack(">I", sidx[pos:pos+4])[0]; pos += 4
        sap_type = (raw >> 28) & 0x07
        entries.append({
            "i": i, "offset": cur_off, "size": raw & 0x0FFFFFFF,
            "dur": dur, "time": round(cur_time, 2), "sap": sap_type in (1, 2),
        })
        cur_off += entries[-1]["size"]
        cur_time += dur / timescale
        if version == 1 and sap_type == 0 and pos + 4 <= len(sidx):
            pos += 4

    # 显示前 12 条
    print(f"\n   {'idx':>4} {'offset':>10} {'size(KB)':>10} {'dur':>8} {'time(s)':>10} SAP")
    print(f"   {'-'*54}")
    for e in entries[:12]:
        print(f"   {e['i']:>4} {e['offset']:>10} {e['size']/1024:>9.1f} {e['dur']:>8} {e['time']:>9.1f}s {'Y' if e['sap'] else 'N'}")

    total_t = sum(e["dur"] for e in entries) / timescale
    avg_kb = sum(e["size"] for e in entries) / len(entries) / 1024
    avg_s = total_t / len(entries)
    print(f"\n   总时长={total_t:.1f}s, 平均GOP={avg_kb:.1f}KB/{avg_s:.1f}s, SAP={sum(1 for e in entries if e['sap'])}/{len(entries)}")
    return {"version": version, "timescale": timescale, "entries": entries, "ref_count": ref_count}

# ==================== 二分查找 ====================

def test_search(entries, timestamps):
    print("\n" + "=" * 50)
    print("Step 5c: 二分查找验证")
    for ts in timestamps:
        lo, hi = 0, len(entries) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if entries[mid]["time"] <= ts:
                lo = mid
            else:
                hi = mid - 1
        best = entries[lo]
        if lo + 1 < len(entries):
            d1, d2 = abs(entries[lo]["time"] - ts), abs(entries[lo+1]["time"] - ts)
            best = entries[lo] if d1 <= d2 else entries[lo+1]
        print(f"   t={ts:>4.0f}s -> entry[{best['i']:>3}] time={best['time']:>6.1f}s offset={best['offset']:>8} size={best['size']/1024:>5.0f}KB {'✅' if best['sap'] else '⚠️'}")

# ==================== 主流程 ====================

print("🔬 Step 4+5: WBI + playurl + sidx")
mixin_key = get_mixin_key()
if not mixin_key:
    print("\n❌ 无法获取 WBI keys")
    exit(1)

# 获取 CID
info_url = f"{BASE}/x/web-interface/view"
for bv in [BV, "BV1GJ411x7h7", "BV1sJ411j7Hq"]:
    resp = requests.get(info_url, params={"bvid": bv}, headers=HEADERS, timeout=15)
    info = resp.json()
    if info.get("code") == 0:
        break

inner = info["data"]
cid = inner["cid"]
print(f"\n📹 {inner['title'][:30]} (CID={cid}, {inner['duration']}s, BV={bv})")

playurl, code = test_playurl(bv, cid, mixin_key)
if not playurl:
    if code == -352:
        print("\n⚠️ WBI key 过期, 重新获取...")
        mixin_key = get_mixin_key()
        if mixin_key:
            playurl, code = test_playurl(bv, cid, mixin_key)
    if not playurl:
        print("\n❌ playurl 获取失败")
        exit(1)

sidx = test_sidx(playurl)
if not sidx:
    print("\n❌ sidx 解析失败")
    exit(1)

dur = inner["duration"]
test_search(sidx["entries"], [0, 10, 30, 60, 120, dur*0.5, dur*0.8, dur-1])

print("\n" + "=" * 50)
print("📊 汇总")
print("-" * 50)
print(f"  WBI:     ✅ mixin_key 获取成功")
print(f"  playurl: ✅ {playurl['width']}x{playurl['height']}")
print(f"  sidx:    ✅ {sidx['ref_count']} entries, {sidx.get('total_t', 0):.0f}s")
print(f"  数据量:  init+sidx ≈ 6KB (vs 完整视频 ~{inner['duration']*500//1000}MB)")
print(f"\n✅ Step 4+5 完成 — sidx 方案可行!")
