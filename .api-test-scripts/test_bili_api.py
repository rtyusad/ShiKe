#!/usr/bin/env python3
"""Step 2: B站 API 联调测试 — info + videoshot + 雪碧图解析验证"""
import requests
import json
import struct
import time
import os
from io import BytesIO
from PIL import Image

PROXY = {}  # 直连即可
HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
    "Referer": "https://www.bilibili.com",
}
BASE = "https://api.bilibili.com"
OUTPUT = "/Users/tboat/Desktop/ai/食谱/ShiKe/.api-test-output"
os.makedirs(OUTPUT, exist_ok=True)

# 测试用 BV 号（找真实美食视频）
BV = "BV1GJ411x7h7"  # 美食作家王刚

def test_info_api():
    """测试 info API"""
    print("=" * 50)
    print("1. info API 测试")
    url = f"{BASE}/x/web-interface/view"
    resp = requests.get(url, params={"bvid": BV}, headers=HEADERS, proxies=PROXY, timeout=15)
    data = resp.json()
    code = data.get("code")
    print(f"   状态码: HTTP {resp.status_code}, B站 code={code}")

    if code != 0:
        print(f"   ❌ 失败: {data.get('message')}")
        # 尝试另一个 BV 号
        return test_info_fallback()

    inner = data["data"]
    info = {
        "bvid": inner["bvid"],
        "title": inner["title"],
        "author": inner["owner"]["name"],
        "mid": inner["owner"]["mid"],
        "duration": inner["duration"],
        "cid": inner["cid"],
        "pic": inner.get("pic", ""),
        "desc": inner.get("desc", "")[:80],
    }
    print(f"   ✅ 标题: {info['title']}")
    print(f"   ✅ UP主: @{info['author']} (mid={info['mid']})")
    print(f"   ✅ 时长: {info['duration']}s ({info['duration']//60}分{info['duration']%60}秒)")
    print(f"   ✅ CID: {info['cid']}")
    return info

def test_info_fallback():
    """备用 BV 号测试"""
    for bv in ["BV1GJ411x7h7", "BV1sJ411j7Hq", "BV1tJ411m7Ht"]:
        print(f"   尝试备用: {bv}")
        url = f"{BASE}/x/web-interface/view"
        resp = requests.get(url, params={"bvid": bv}, headers=HEADERS, proxies=PROXY, timeout=15)
        data = resp.json()
        if data.get("code") == 0:
            inner = data["data"]
            info = {
                "bvid": inner["bvid"],
                "title": inner["title"],
                "author": inner["owner"]["name"],
                "mid": inner["owner"]["mid"],
                "duration": inner["duration"],
                "cid": inner["cid"],
            }
            print(f"   ✅ 标题: {info['title']}")
            print(f"   ✅ CID: {info['cid']}")
            return info
    print("   ❌ 所有 BV 号均失败")
    return None

def test_videoshot_api(bvid):
    """测试 videoshot API"""
    print("\n" + "=" * 50)
    print("2. videoshot API 测试")
    url = f"{BASE}/x/player/videoshot"

    # index=1: JSON 时间戳
    resp = requests.get(url, params={"bvid": bvid, "index": 1}, headers=HEADERS, proxies=PROXY, timeout=15)
    data = resp.json()
    code = data.get("code")
    print(f"   状态码: HTTP {resp.status_code}, B站 code={code}")

    if code != 0:
        print(f"   ❌ 失败: {data.get('message')}")
        return None

    inner = data.get("data", data)

    # 解析时间戳
    index_arr = inner.get("index", [])
    print(f"   ✅ 帧数: {len(index_arr)}")
    print(f"   ✅ 时间戳样本: {index_arr[:10]}...")

    # 获取雪碧图URL
    images = inner.get("image", [])
    if not images:
        print("   ❌ 无雪碧图数据")
        return None

    sprite_url = images[0]
    # 处理各种URL格式
    if sprite_url.startswith("//"):
        sprite_url = "https:" + sprite_url
    elif sprite_url.startswith("http://"):
        sprite_url = sprite_url.replace("http://", "https://")
    print(f"   ✅ 雪碧图URL: {sprite_url[:80]}...")

    # 下载雪碧图
    img_resp = requests.get(sprite_url, headers=HEADERS, proxies=PROXY, timeout=30)
    sprite_path = os.path.join(OUTPUT, "sprite_sheet.jpg")
    with open(sprite_path, "wb") as f:
        f.write(img_resp.content)
    size_kb = len(img_resp.content) / 1024
    print(f"   ✅ 雪碧图已保存: {sprite_path} ({size_kb:.0f}KB)")

    # 打开图像获取尺寸
    img = Image.open(BytesIO(img_resp.content))
    print(f"   ✅ 雪碧图尺寸: {img.size[0]}×{img.size[1]}px")

    return {
        "index": index_arr,
        "sprite_path": sprite_path,
        "image_size": img.size,
        "sprite_image": img,
    }

def test_sprite_parsing(sprite_data, info):
    """测试雪碧图切分（对标 SpriteSheetParser）"""
    print("\n" + "=" * 50)
    print("3. 雪碧图切分测试 (对标 SpriteSheetParser)")

    img = sprite_data["sprite_image"]
    timestamps = sprite_data["index"]
    w, h = img.size

    columns = 10
    rows = max(1, len(timestamps) // columns)
    cell_w = w // columns
    cell_h = h // rows

    print(f"   网格: {columns}×{rows}")
    print(f"   每格: {cell_w}×{cell_h}px")
    print(f"   时间戳数量: {len(timestamps)}")

    # 切分前几个格子做验证
    cell_dir = os.path.join(OUTPUT, "cells")
    os.makedirs(cell_dir, exist_ok=True)

    cells = []
    for i in range(min(6, len(timestamps))):
        col = i % columns
        row = i // columns
        x = col * cell_w
        y = row * cell_h
        cell = img.crop((x, y, x + cell_w, y + cell_h))

        ts = timestamps[i]
        m, s = ts // 60, ts % 60
        cell_path = os.path.join(cell_dir, f"cell_{i:02d}_{m:02d}{s:02d}.jpg")
        cell.save(cell_path)
        cells.append((i, col, row, ts, cell_path))
        print(f"    [{i:02d}] col={col} row={row} ts={m:02d}:{s:02d} → {cell_path}")

    print(f"   ✅ 切分验证完成，{len(cells)} 帧已保存到 {cell_dir}/")
    return cells

def test_sidx_feasibility(info):
    """测试 playurl API 可用性（为 Step 4-5 做准备）"""
    print("\n" + "=" * 50)
    print("4. playurl API 探测 (为 sidx 做准备)")

    # 先获取 WBI 密钥
    nav_url = f"{BASE}/x/web-interface/nav"
    resp = requests.get(nav_url, headers=HEADERS, proxies=PROXY, timeout=15)
    nav = resp.json()

    if nav.get("code") != 0:
        print(f"   ⚠️ nav API 失败 (需要 cookie?)")
        return None

    wbi_img = nav["data"]["wbi_img"]
    print(f"   ✅ WBI keys 获取成功")

    # 直接尝试获取 playurl (不带签名，看是否可获取 SegmentBase)
    cid = info["cid"]
    play_url = f"{BASE}/x/player/playurl"
    params = {
        "bvid": info["bvid"],
        "cid": cid,
        "fnval": 16,  # DASH
        "fnver": 0,
        "fourk": 1,
    }
    resp = requests.get(play_url, params=params, headers=HEADERS, proxies=PROXY, timeout=15)
    play_data = resp.json()

    if play_data.get("code") != 0:
        print(f"   ⚠️ playurl 需要 WBI 签名: code={play_data.get('code')}, msg={play_data.get('message')}")
        return None

    # 解析 DASH → SegmentBase
    dash = play_data.get("data", {}).get("dash", {})
    videos = dash.get("video", [])
    if not videos:
        print("   ❌ 无 DASH 视频流")
        return None

    # 选最高清晰度
    video = sorted(videos, key=lambda v: v.get("width", 0), reverse=True)[0]
    seg = video.get("segment_base", {})

    result = {
        "width": video.get("width"),
        "height": video.get("height"),
        "bandwidth": video.get("bandwidth"),
        "codecs": video.get("codecs"),
        "init_range": seg.get("initialization"),
        "index_range": seg.get("index_range"),
        "base_url": video.get("base_url", video.get("baseUrl", "")),
    }
    print(f"   ✅ 清晰度: {result['width']}×{result['height']}, {result['bandwidth']//1000}kbps")
    print(f"   ✅ initRange: {result['init_range']}")
    print(f"   ✅ indexRange: {result['index_range']}")
    print(f"   ✅ base_url: {result['base_url'][:80]}...")
    return result

# ========== 运行 ==========
print("🔬 B站 API 联调测试 — Step 2")
print(f"📺 测试 BV 号: {BV}\n")

info = test_info_api()
if not info:
    print("\n❌ info API 测试失败，终止")
    exit(1)

sprite = test_videoshot_api(info["bvid"])
if sprite:
    cells = test_sprite_parsing(sprite, info)

sidx = test_sidx_feasibility(info)

# 汇总
print("\n" + "=" * 50)
print("📊 测试汇总")
print("-" * 50)
if info:
    print(f"  info API:      ✅ {info['title']} (CID={info['cid']})")
if sprite:
    print(f"  videoshot API: ✅ {len(sprite['index'])} 帧, {sprite['image_size'][0]}×{sprite['image_size'][1]}px")
if 'cells' in dir() and cells:
    print(f"  雪碧图切分:    ✅ {len(cells)} 帧验证通过")
if sidx:
    print(f"  playurl API:   ✅ {sidx['width']}×{sidx['height']}, sidx={sidx['index_range']}")
else:
    print(f"  playurl API:   ⚠️ 需 WBI 签名 (Step 4)")

print(f"\n📁 输出目录: {OUTPUT}")
print("✅ Step 2 联调完成")
