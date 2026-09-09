#!/usr/bin/env python3
"""与 /workspace/apk-tool/SDRApkParser.m 中 SDRBinaryXml 1:1 等价的 AXML 解析验证脚本。
用于在真实 APK 上验证解析逻辑，定位 ObjC 实现的 bug。"""
import struct
import sys
import zipfile

CHUNK_STRING_POOL = 0x0001
CHUNK_RES_MAP = 0x0180
CHUNK_START_NS = 0x0100
CHUNK_END_NS = 0x0101
CHUNK_START_ELEMENT = 0x0102
CHUNK_END_ELEMENT = 0x0103
CHUNK_CDATA = 0x0104

ANDROID_NS = "http://schemas.android.com/apk/res/android"


class Element:
    def __init__(self, name):
        self.name = name
        self.attrs = {}
        self.children = []

    def attr(self, name):
        a = self.attrs.get(name)
        if a is not None:
            return a
        return self.attrs.get("android:" + name)


def parse_axml(data):
    if len(data) < 8 or struct.unpack_from("<H", data, 0)[0] != 0x0003:
        raise ValueError("invalid axml header")
    strings = []
    stack = []
    root = None
    off = 8
    n = len(data)
    while off + 8 <= n:
        typ = struct.unpack_from("<H", data, off)[0]
        header_size = struct.unpack_from("<H", data, off + 2)[0]
        size = struct.unpack_from("<I", data, off + 4)[0]
        if size < header_size or off + size > n:
            break
        if typ == CHUNK_STRING_POOL:
            strings = parse_string_pool(data, off)
        elif typ == CHUNK_START_ELEMENT:
            el = parse_start_element(data, off, strings)
            if el is not None:
                if not stack:
                    root = el
                else:
                    stack[-1].children.append(el)
                stack.append(el)
        elif typ == CHUNK_END_ELEMENT:
            if stack:
                stack.pop()
        off += size
    return root, strings


def pool_string(data, sp, idx):
    string_count = struct.unpack_from("<I", data, sp + 8)[0]
    flags = struct.unpack_from("<I", data, sp + 16)[0]
    strings_start = struct.unpack_from("<I", data, sp + 20)[0]
    if idx >= string_count:
        return None
    str_off = struct.unpack_from("<I", data, sp + 28 + idx * 4)[0] + strings_start
    s_off = sp + str_off
    utf8 = (flags & 0x100) != 0
    if utf8:
        b0 = data[s_off]
        if b0 & 0x80:
            ln = ((b0 & 0x7F) << 8) | data[s_off + 1]
            s_off += 2
        else:
            ln = b0
            s_off += 1
        return data[s_off:s_off + ln].decode("utf-8", errors="replace")
    else:
        ln = struct.unpack_from("<H", data, s_off)[0]
        s_off += 2
        return data[s_off:s_off + ln * 2].decode("utf-16-le", errors="replace")


def parse_string_pool(data, off):
    sp = off
    string_count = struct.unpack_from("<I", data, sp + 8)[0]
    res = []
    for i in range(string_count):
        res.append(pool_string(data, sp, i) or "")
    return res


def parse_start_element(data, off, strings):
    chunk = off
    ns_idx = struct.unpack_from("<I", data, chunk + 16)[0]
    name_idx = struct.unpack_from("<I", data, chunk + 20)[0]
    attr_count = struct.unpack_from("<H", data, chunk + 28)[0]

    def string_at(idx):
        if idx == 0xFFFFFFFF or idx >= len(strings):
            return None
        return strings[idx]

    el = Element(string_at(name_idx) or "")
    ap = chunk + 36
    for _ in range(attr_count):
        a_ns = struct.unpack_from("<I", data, ap)[0]
        a_name = struct.unpack_from("<I", data, ap + 4)[0]
        a_raw = struct.unpack_from("<I", data, ap + 8)[0]
        vsize = struct.unpack_from("<H", data, ap + 12)[0]
        data_type = data[ap + 15]
        adata = struct.unpack_from("<I", data, ap + 16)[0]

        short_name = string_at(a_name) or ""
        ns = string_at(a_ns)
        full_name = short_name
        if ns and ns != ANDROID_NS:
            full_name = ns.rsplit("/", 1)[-1] + ":" + short_name
        if ns == ANDROID_NS:
            full_name = "android:" + short_name

        value = ""
        if data_type == 0x03:      # string
            value = string_at(adata) or ""
        elif data_type == 0x10:    # int dec
            value = str(struct.unpack("<i", struct.pack("<I", adata))[0])
        elif data_type == 0x11:    # int hex
            value = "0x%08x" % adata
        elif data_type == 0x12:    # bool
            value = "true" if adata else "false"
        elif data_type == 0x01:    # reference
            value = "@0x%08x" % adata
        elif data_type == 0x00:    # null
            value = ""
        else:
            value = str(struct.unpack("<i", struct.pack("<I", adata))[0])
        el.attrs[full_name] = value
        ap += 20
    return el


def main(path):
    with zipfile.ZipFile(path) as zf:
        manifest = zf.read("AndroidManifest.xml")
    root, strings = parse_axml(manifest)
    print("root:", root.name if root else None)
    if root:
        print("package:", root.attr("package"))
        print("versionName:", root.attr("versionName"))
        print("versionCode:", root.attr("versionCode"))
        for c in root.children:
            if c.name == "uses-sdk":
                print("minSdk:", c.attr("minSdkVersion"), "targetSdk:", c.attr("targetSdkVersion"))
            if c.name == "application":
                print("appLabel:", c.attr("label"))
                for gc in c.children:
                    if gc.name == "activity":
                        n = gc.attr("name") or ""
                        print("  activity:", n)


if __name__ == "__main__":
    main(sys.argv[1])