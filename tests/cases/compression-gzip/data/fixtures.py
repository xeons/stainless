# Makes the compression-gzip fixtures in the working directory, with the
# system's gzip and Python's zlib. Run on Linux; the text is the one
# gzip.sl makes for itself. gzip records each file's time, so its output
# differs from run to run in those four bytes.
import os, struct, subprocess, zlib

WORDS = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
         "stream", "window", "deflate", "huffman", "code", "length",
         "distance", "block", "literal", "match", "inflate", "gzip"]


def text(size):
    state = 12345
    out = bytearray()
    while len(out) < size:
        state = (state * 1103515245 + 12345) & 0xFFFFFFFF
        out += WORDS[(state >> 16) % 20].encode()
        out += b" " if (state >> 8) & 15 else b"\n"
    return bytes(out)


t = text(70000)
open("text.txt", "wb").write(t)
subprocess.run("gzip -9 -c text.txt > text9.gz", shell=True, check=True)
subprocess.run("gzip -1 -c text.txt > text1.gz", shell=True, check=True)
open("first.txt", "wb").write(t[:35000])
open("second.txt", "wb").write(t[35000:])
subprocess.run("gzip -6 -c first.txt > a.gz && gzip -6 -c second.txt > b.gz && cat a.gz b.gz > two.gz",
               shell=True, check=True)
open("text.zlib", "wb").write(zlib.compress(t, 9))
raw = zlib.compressobj(6, zlib.DEFLATED, -15)
open("text.deflate", "wb").write(raw.compress(t) + raw.flush())

# Every optional header field, with the header CRC, over the first 1000 bytes.
body = t[:1000]
raw = zlib.compressobj(9, zlib.DEFLATED, -15)
deflated = raw.compress(body) + raw.flush()
header = bytearray(b"\x1f\x8b\x08")
header.append(0x01 | 0x02 | 0x04 | 0x08 | 0x10)
header += struct.pack("<I", 1700000000) + b"\x02\x03"
extra = b"AB\x04\x00test"
header += struct.pack("<H", len(extra)) + extra
header += b"text.txt\x00" + b"a comment\x00"
header += struct.pack("<H", zlib.crc32(header) & 0xFFFF)
member = bytes(header) + deflated + struct.pack("<II", zlib.crc32(body), len(body))
open("fields.gz", "wb").write(member)

subprocess.run("gzip -t text9.gz text1.gz two.gz fields.gz", shell=True, check=True)
for name in ["text.txt", "first.txt", "second.txt", "a.gz", "b.gz"]:
    os.remove(name)

