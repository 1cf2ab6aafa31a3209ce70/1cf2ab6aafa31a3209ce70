"""Minimal Mach-O reader for the built-bundle gates (standard library only).

Reads thin 64-bit Mach-O files and universal files with 32- or 64-bit fat
headers: segments and sections, LC_UUID, the symbol and string tables and the
code signature blob. It reads layout only; scripts/check-required-reason-apis.py
and the capability scan use the Xcode tools (nm, otool, swift-demangle) for
symbol content.
"""
from pathlib import Path
import struct

# Universal headers: (byte order, 64-bit fat_arch entries). `lipo -fat64` writes the
# 64-bit form, which a gate that knows only the 32-bit form would skip entirely.
FAT_MAGIC = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
             b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
MAGIC = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce"} | set(FAT_MAGIC)
LC_SEGMENT_64, LC_SYMTAB, LC_UUID, LC_CODE_SIGNATURE = 0x19, 0x2, 0x1B, 0x1D


def is_macho(path):
    path = Path(path)
    if not path.is_file() or path.is_symlink():
        return False
    with path.open("rb") as stream:
        return stream.read(4) in MAGIC


def files(bundle):
    """Every Mach-O file inside a bundle directory."""
    return sorted(path for path in Path(bundle).rglob("*") if is_macho(path))


def _slice(data, base, size):
    magic = data[base:base + 4]
    if magic != b"\xcf\xfa\xed\xfe":
        raise ValueError(f"unsupported Mach-O slice magic {magic.hex()} (64-bit little-endian only)")
    cputype, _, _, ncmds, _ = struct.unpack_from("<iiIII", data, base + 4)
    offset = base + 32
    regions, uuid, uuid_offset, symtab, signature = [], None, None, None, None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmd == LC_SEGMENT_64:
            segname = data[offset + 8:offset + 24].rstrip(b"\0").decode()
            fileoff, filesize = struct.unpack_from("<QQ", data, offset + 40)
            nsects = struct.unpack_from("<I", data, offset + 64)[0]
            regions.append((segname, base + fileoff, filesize))
            for index in range(nsects):
                section = offset + 72 + index * 80
                sectname = data[section:section + 16].rstrip(b"\0").decode()
                size = struct.unpack_from("<Q", data, section + 40)[0]
                file_offset, _, _, _, flags = struct.unpack_from("<IIIII", data, section + 48)
                if file_offset and (flags & 0xFF) not in (0x1, 0xC, 0x12):  # zerofill sections have no bytes
                    regions.append((f"{segname},{sectname}", base + file_offset, size))
        elif cmd == LC_UUID:
            uuid, uuid_offset = data[offset + 8:offset + 24].hex().upper(), offset + 8
        elif cmd == LC_SYMTAB:
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, offset + 8)
            symtab = (base + symoff, nsyms, base + stroff, strsize)
            regions.append(("symbol table", base + symoff, nsyms * 16))
            regions.append(("string table", base + stroff, strsize))
        elif cmd == LC_CODE_SIGNATURE:
            dataoff, datasize = struct.unpack_from("<II", data, offset + 8)
            signature = (base + dataoff, datasize)
            regions.append(("code signature", base + dataoff, datasize))
        offset += cmdsize
    regions.append(("load commands", base, offset - base))
    return {"cputype": cputype, "base": base, "size": size, "uuid": uuid, "uuid_offset": uuid_offset, "symtab": symtab,
            "signature": signature, "regions": regions}


def parse(path):
    """File bytes and slices, each with its regions, UUID, symbol table and signature."""
    data = Path(path).read_bytes()
    return data, parse_bytes(data)


def parse_bytes(data):
    magic = data[:4]
    if magic in FAT_MAGIC:
        endian, wide = FAT_MAGIC[magic]
        count = struct.unpack_from(endian + "I", data, 4)[0]
        entry, width = ("iiQQII", 32) if wide else ("iiIII", 20)
        slices = []
        for index in range(count):
            _, _, offset, size = struct.unpack_from(endian + entry, data, 8 + index * width)[:4]
            slices.append(_slice(data, offset, size))
        return slices
    return [_slice(data, 0, len(data))]


def region_at(slices, offset):
    """The most specific named region (section before segment) that contains a file offset."""
    best = None
    for item in slices:
        for name, start, size in item["regions"]:
            if start <= offset < start + size and (best is None or size < best[2]):
                best = (name, start, size)
    return best[0] if best else "outside any region"


def string_at(data, table, offset):
    """The NUL-terminated string in a string table that contains `offset`."""
    start = data.rfind(b"\0", table, offset) + 1
    end = data.find(b"\0", offset)
    return data[max(start, table):end].decode(errors="replace")
