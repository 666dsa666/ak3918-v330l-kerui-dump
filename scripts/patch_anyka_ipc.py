#!/usr/bin/env python3
"""Build a local-only anyka_ipc for the Anyka AK3918EN080 V330L (v33.53.61).

Turns the stock application (3,382,008 B, MD5 ab81807d9e2d9d5dc946419af43e69b6)
into a build that:
  - never establishes a Tuya MQTT session (mqtt_connect fails, no retry worker),
  - starts RTSP + ONVIF locally right after media init,
  - keeps the VI->VENC channels bound so real video frames are produced,
  - never tears RTSP/ONVIF down (even if the WAN disappears),
  - keeps the status LED steady.

Usage:
    python patch_anyka_ipc.py anyka_ipc_stock.bin anyka_ipc_patched.bin

Requires: capstone, pyelftools.
The script validates every original instruction word and aborts on any mismatch,
so it only applies to the exact build it was written for.
"""
import hashlib
import struct
import sys

from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CS_MODE_LITTLE_ENDIAN
from elftools.elf.elffile import ELFFile

EXPECTED_STOCK_MD5 = "ab81807d9e2d9d5dc946419af43e69b6"
EXPECTED_PATCHED_MD5 = "1841dcdac0db4a0815a8656e8f80461d"
EXPECTED_SIZE = 3382008

SRC = sys.argv[1] if len(sys.argv) > 1 else "anyka_ipc_stock.bin"
OUT = sys.argv[2] if len(sys.argv) > 2 else "anyka_ipc_patched.bin"

with open(SRC, "rb") as fh:
    data = bytearray(fh.read())
if len(data) != EXPECTED_SIZE:
    sys.exit("unexpected size %d (expected %d)" % (len(data), EXPECTED_SIZE))
if hashlib.md5(data).hexdigest() != EXPECTED_STOCK_MD5:
    sys.exit("unexpected stock MD5 (expected %s) - wrong build" % EXPECTED_STOCK_MD5)

with open(SRC, "rb") as fh:
    elf = ELFFile(fh)
    segs = [(s["p_vaddr"], s["p_offset"], s["p_filesz"])
            for s in elf.iter_segments() if s["p_type"] == "PT_LOAD"]


def va2off(va):
    for v, o, sz in segs:
        if v <= va < v + sz:
            return o + (va - v)
    raise ValueError("VA 0x%x is not mapped" % va)


def arm_b(addr, target):
    return 0xEA000000 | (((target - (addr + 8)) >> 2) & 0xFFFFFF)


def arm_bl(addr, target):
    return 0xEB000000 | (((target - (addr + 8)) >> 2) & 0xFFFFFF)


BX_LR = 0xE12FFF1E
NOP = 0xE1A00000
MVN_R0_0 = 0xE3E00000
MOV_R0_0 = 0xE3A00000
MOV_R0_1 = 0xE3A00001

# (VA, new word, expected old word or None, description)
PATCHES = [
    # RTSP/ONVIF must never be torn down
    (0x0009DF6C, BX_LR, 0xE92D41F3, "ak_rtsp_exit entry -> bx lr"),
    (0x0027AB60, BX_LR, None, "onvif_stop entry -> bx lr"),
    (0x000AEA34, BX_LR, arm_b(0x0AEA34, 0x9DF6C), "set_onvif_switch disable branch -> bx lr"),
    (0x000AEAE4, NOP, None, "direct bl ak_rtsp_exit -> nop"),
    # kill the cloud session
    (0x001FB7B4, MVN_R0_0, None, "mqtt_connect -> mvn r0,#0 (return -1)"),
    (0x001FB7B8, BX_LR, None, "mqtt_connect -> bx lr"),
    # start RTSP locally after media init; keep media_chsub_enable intact
    (0x000B6C8C, arm_b(0x0B6C8C, 0x0B6C90), 0x0A000002, "beq online -> b 0xB6C90 (skip MQTT wait)"),
    (0x000B6C90, MOV_R0_1, None, "mov r0,#1 (ONVIF/RTSP switch ON)"),
    (0x000B6C94, arm_bl(0x0B6C94, 0x0AE9F0), None, "bl set_onvif_switch -> ak_rtsp_init"),
    (0x000B6C98, arm_b(0x0B6C98, 0x0B6CA0), None, "b 0xB6CA0 (keep media_chsub_enable)"),
    # LED: blink modes -> steady off
    (0x000B43B8, arm_b(0x0B43B8, 0x0B43F4), arm_b(0x0B43B8, 0x0B4408), "LED mode 3 -> led.sh off"),
    (0x000B43BC, arm_b(0x0B43BC, 0x0B43F4), arm_b(0x0B43BC, 0x0B4400), "LED mode 4 -> led.sh off"),
    (0x000B43C4, arm_b(0x0B43C4, 0x0B43F4), arm_b(0x0B43C4, 0x0B4400), "LED mode 6 -> led.sh off"),
    (0x000B43C8, arm_b(0x0B43C8, 0x0B43F4), arm_b(0x0B43C8, 0x0B4408), "LED mode 7 -> led.sh off"),
    # no MQTT retry worker -> no SYN churn to :8883
    (0x001526A8, MOV_R0_0, 0xE3500000, "mqtt_client_start -> mov r0,#0"),
    (0x001526AC, BX_LR, None, "mqtt_client_start -> bx lr (return 0)"),
]

md = Cs(CS_ARCH_ARM, CS_MODE_ARM | CS_MODE_LITTLE_ENDIAN)
for va, new, expect, why in PATCHES:
    off = va2off(va)
    old = struct.unpack_from("<I", data, off)[0]
    if expect is not None and old != expect:
        sys.exit("ABORT at 0x%08x: found %08x, expected %08x (%s)" % (va, old, expect, why))
    struct.pack_into("<I", data, off, new)
    dis = list(md.disasm(struct.pack("<I", new), va))
    txt = (dis[0].mnemonic + " " + dis[0].op_str) if dis else "(data)"
    print("0x%08x off=0x%06x  %08x -> %08x  [%-26s] %s" % (va, off, old, new, txt, why))

# media_chsub_enable must survive: it binds VI->VENC and produces frames
off = va2off(0x0B6CA0)
w = struct.unpack_from("<I", data, off)[0]
if w != arm_bl(0x0B6CA0, 0x97D98):
    sys.exit("media_chsub_enable at 0xB6CA0 was clobbered (0x%08x)" % w)
print("OK: 0xB6CA0 still 'bl media_chsub_enable' (0x%08x)" % w)

with open(OUT, "wb") as fh:
    fh.write(bytes(data))

digest = hashlib.md5(bytes(data)).hexdigest()
print("written:", OUT, len(data), "bytes")
print("MD5:", digest)
if digest != EXPECTED_PATCHED_MD5:
    print("WARNING: expected patched MD5", EXPECTED_PATCHED_MD5)
else:
    print("OK: matches the published patched build")
