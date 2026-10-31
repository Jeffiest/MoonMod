"""Patches a Dark Cloud compiled script (.stb): new code, strings and programs appended, and hooks into the old code.

    from stbpatch import Script
    s = Script(open("event.stb", "rb").read())
    f = s.function(["PUSH 1", ...], args=0, locals=0)     # a new function, its record's code offset
    s.retarget_call(0x115dc, f)                            # an existing CALL now calls it
    s.hook_ext(0x087a8, ["LOAD_CHARA(6, 'baby.cfg')"])     # code run right after an existing EXT
    s.add_program(12, f)                                   # program 12 runs it
    open("patched.stb", "wb").write(s.build())

The layout is the one tools/stb/stbdis.py reads and the port's runscript.cpp runs: a header {unk, main, code, prog,
prog_num}, 12-byte instructions {op, arg1, arg2}, 16-byte function records {addr, name, local, arg}. Strings PUSH
pushes, jump targets, the CALL operand and function addresses are offsets into the code section, which runs to the
end of the file, so what is new goes on the end and the program table is moved after it.

The VM skips JMPs and EXTs while a scene is being skipped (skip_wait), but always performs a CALL, so hooks are calls:

- retarget_call(at, record): the CALL at `at` calls `record` instead (give it the same args; call the old one in it
  with old_record(at)).
- hook_ext(at, code): the EXT at `at`, which must be followed by a constant PUSH, is replaced by a CALL of a new
  function that takes the EXT's operands as its arguments, does the EXT itself, then `code`, and returns the constant
  the PUSH pushed; the PUSH becomes op 22, which the VM does nothing with. The stack ends as it would have.

Instructions are written as text:
    PUSH 5 | PUSH 1.5f | PUSH "name"      constants
    LOAD 0 | LOAD_ADDR 0 | STORE | POP     local slots (plain locals)
    EXT NAME n                            an external function by name with n arguments pushed after its number
    NAME(a, b, ...)                       sugar: PUSH the number of NAME, PUSH each argument, EXT; an argument is a
                                          number, 1.5f, "string" or &n (the address of local n)
    CMP == | JMP label | JMP_FALSE label | JMP_TRUE label | CALL record | RET | WAIT | NOT | AND | OR | ADD ...
    label:                                a jump target in this function
"""

import re
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import stbdis  # noqa: E402

OPS = {v: k for k, v in stbdis.OPS.items()}
CMP = {v: k for k, v in stbdis.CMP.items()}
NOP = 22
PORT = Path("E:/Gauntlet-build/Chronicle/port")


def ext_numbers(table="event", port=PORT):
    return {name: no for no, name in stbdis.ext_names(Path(port), table).items()}


def _f32(value):
    return struct.unpack("<i", struct.pack("<f", value))[0]


class Script:
    def __init__(self, data, table="event", port=PORT):
        self.data = bytearray(data)
        self.unk, self.main, self.code, self.prog, self.prog_num = struct.unpack_from("<5i", data, 0)
        self.progs = [list(struct.unpack_from("<2i", data, self.prog + 8 * i)) for i in range(self.prog_num)]
        self.ext = ext_numbers(table, port)
        self.tail = bytearray()  # appended to the code section (its offsets go on from the file's end)

    # --- reading -----------------------------------------------------------------------------------------------------
    def insn(self, at):
        return struct.unpack_from("<3i", self.data, self.code + at)

    def old_record(self, at):
        """The record (code offset) the CALL at `at` calls."""
        op, _, record = self.insn(at)
        assert op == OPS["CALL"], "no CALL at %#x" % at
        return record

    def program_record(self, no):
        """The record (code offset) of program `no`."""
        return next(rec - self.code for n, rec in self.progs if n == no)

    # --- appending ---------------------------------------------------------------------------------------------------
    def _here(self):
        return len(self.data) - self.code + len(self.tail)

    def _align(self):
        while (len(self.data) + len(self.tail)) % 4:
            self.tail += b"\0"

    def string(self, text):
        self._align()
        at = self._here()
        self.tail += text.encode("cp932") + b"\0"
        return at

    def function(self, lines, args=0, locals=None):
        """Appends a function made of `lines` (see the module notes); its record's code offset."""
        locals = args if locals is None else max(locals, args)
        lines = [l.strip() for l in lines if l.strip() and not l.strip().startswith("#")]
        program = []
        for line in lines:
            program += self._expand(line)
        # labels: two passes (strings are placed after the code, so their offsets are known only once it is)
        self._align()
        start = self._here()
        labels, n = {}, 0
        for item in program:
            if item[0] == "label":
                labels[item[1]] = start + 12 * n
            else:
                n += 1
        strings_at = start + 12 * n
        pending_strings = []
        code = bytearray()
        for item in program:
            if item[0] == "label":
                continue
            op, a1, a2 = item
            if isinstance(a1, str) and a1.startswith("@"):
                a1 = labels[a1[1:]]
            if isinstance(a2, tuple) and a2[0] == "str":
                pending_strings.append(a2[1])
                a2 = ("strref", len(pending_strings) - 1)
            code += struct.pack("<3i", op, a1, 0) if isinstance(a2, tuple) else struct.pack("<3i", op, a1, a2)
            if isinstance(a2, tuple):
                code[-4:] = b"STR" + bytes([a2[1]])  # filled below
        # strings after the code
        string_offsets = []
        blob = bytearray()
        for text in pending_strings:
            while (strings_at + len(blob)) % 4:
                blob += b"\0"
            string_offsets.append(strings_at + len(blob))
            blob += text.encode("cp932") + b"\0"
        for i in range(0, len(code), 12):
            if code[i + 8:i + 11] == b"STR":
                struct.pack_into("<i", code, i + 8, string_offsets[code[i + 11]])
        self.tail += code + blob
        self._align()
        record = self._here()
        self.tail += struct.pack("<iIii", start, 0, locals, args)
        return record

    def _expand(self, line):
        if line.endswith(":"):
            return [("label", line[:-1])]
        m = re.fullmatch(r"([A-Z_][A-Z0-9_]*)\((.*)\)", line)
        if m and m.group(1) in self.ext:
            name, inner = m.group(1), m.group(2).strip()
            values = [v.strip() for v in re.findall(r'"[^"]*"|[^,]+', inner)] if inner else []
            out = [(OPS["PUSH"], 1, self.ext[name])]
            for v in values:
                out.append(self._push_or_addr(v))
            out.append((OPS["EXT"], len(values) + 1, 0))
            return out
        parts = line.split(None, 1)
        op, rest = parts[0], parts[1] if len(parts) > 1 else ""
        if op == "PUSH":
            return [self._push_or_addr(rest)]
        if op in ("LOAD", "LOAD_ADDR"):
            return [(OPS[op], int(rest), 1)]
        if op == "EXT":
            name, n = rest.split()
            return [(OPS["PUSH"], 1, self.ext[name]), (OPS["EXT"], int(n) + 1, 0)]
        if op == "EXT_RAW":
            return [(OPS["EXT"], int(rest), 0)]
        if op == "CMP":
            return [(OPS["CMP"], CMP[rest], 0)]
        if op in ("JMP", "JMP_FALSE", "JMP_TRUE"):
            return [(OPS[op], "@" + rest, 0)]
        if op == "CALL":
            return [(OPS["CALL"], 0, int(rest, 0))]
        if op == "NOP":
            return [(NOP, 0, 0)]
        return [(OPS[op], 0, 0)]

    def _push_or_addr(self, v):
        v = v.strip()
        if v.startswith("&"):
            return (OPS["LOAD_ADDR"], int(v[1:]), 1)
        if v.startswith('"'):
            return (OPS["PUSH"], 3, ("str", v[1:-1]))
        if v.endswith("f") or "." in v:
            return (OPS["PUSH"], 2, _f32(float(v.rstrip("f"))))
        return (OPS["PUSH"], 1, int(v, 0))

    # --- hooking -----------------------------------------------------------------------------------------------------
    def _put(self, at, op, a1, a2):
        struct.pack_into("<3i", self.data, self.code + at, op, a1, a2)

    def retarget_call(self, at, record):
        op, a1, _ = self.insn(at)
        assert op == OPS["CALL"], "no CALL at %#x" % at
        self._put(at, op, a1, record)

    def hook_ext(self, at, lines, locals=0):
        """Runs `lines` right after the EXT at `at` (see the module notes); the hook function's record."""
        op, argc, _ = self.insn(at)
        assert op == OPS["EXT"], "no EXT at %#x" % at
        nop, kind, value = self.insn(at + 12)
        assert nop == OPS["PUSH"] and kind in (1, 2), "the EXT at %#x is not followed by a constant PUSH" % at
        body = ["LOAD %d" % i for i in range(argc)] + ["EXT_RAW %d" % argc]
        body += list(lines)
        ret = "PUSH %d" % value if kind == 1 else "PUSH %rf" % struct.unpack("<f", struct.pack("<i", value))[0]
        body += [ret, "RET"]
        record = self.function(body, args=argc, locals=argc + locals)
        self._put(at, OPS["CALL"], 0, record)
        self._put(at + 12, NOP, 0, 0)
        return record

    def add_program(self, no, record):
        """Program `no` runs the function at `record` (replacing one of that number)."""
        self.progs = [p for p in self.progs if p[0] != no]
        self.progs.append([no, self.code + record])

    # --- writing -----------------------------------------------------------------------------------------------------
    def build(self):
        out = bytearray(self.data) + self.tail
        while len(out) % 4:
            out += b"\0"
        prog = len(out)
        for no, rec in self.progs:
            out += struct.pack("<2i", no, rec)
        struct.pack_into("<5i", out, 0, self.unk, self.main, self.code, prog, len(self.progs))
        return bytes(out)
