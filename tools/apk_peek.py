#!/usr/bin/env python3
"""检查测试 APK 的结构：dex、图标、manifest 大小。"""
import sys
import zipfile

path = sys.argv[1]
with zipfile.ZipFile(path) as zf:
    names = zf.namelist()
    dex = [n for n in names if n.endswith(".dex")]
    icons = [n for n in names
             if ("mipmap" in n or "drawable" in n)
             and n.endswith(".png")
             and "ic_launcher" in n.lower()]
    print("dex:", dex)
    print("icons:", icons[:8])
    print("mipmap-xxxhdpi/ic_launcher.png present:",
          "res/mipmap-xxxhdpi/ic_launcher.png" in names)
    manifest = zf.read("AndroidManifest.xml")
    print("manifest size:", len(manifest))
    # 看有哪些 mipmap 目录
    dirs = sorted({n.split("/")[1] for n in names if n.startswith("res/")})
    print("res dirs sample:", dirs[:20])