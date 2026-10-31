"""Disassembles a Dark Cloud compiled script (.stb) into readable text.

    python tools/stb/stbdis.py FILE [--table event|monster] [--prog N ...] [--port DIR]

The layout is the one port/src/game/runscript.cpp reads: a header {unk, main, code, prog, prog_num}, a program table
of {no, func} pairs, 16-byte function records {addr, name, local, arg} and 12-byte instructions {op, arg1, arg2}, all
little-endian 32-bit words. External-function names come from the port's own tables (event scripts: editloop3.cpp
and btsysscript.cpp; monster scripts: runscript_opcodes.cpp), so --port names the Chronicle port folder.

Without --prog every program is listed; with it, the named programs and every function they reach.
"""
import argparse
import re
import struct
import sys
from pathlib import Path

OPS = {1: 'LOAD', 2: 'LOAD_ADDR', 3: 'PUSH', 4: 'POP', 5: 'STORE', 6: 'ADD', 7: 'SUB', 8: 'MUL', 9: 'DIV', 10: 'MOD',
       11: 'NEG', 12: 'ITOF', 13: 'FTOI', 14: 'CMP', 15: 'RET', 16: 'JMP', 17: 'JMP_FALSE', 18: 'JMP_TRUE', 19: 'CALL',
       20: 'PRINT', 21: 'EXT', 23: 'WAIT', 24: 'AND', 25: 'OR', 26: 'NOT', 27: 'END', 28: 'SKIP_END', 29: 'SIN',
       30: 'COS'}
CMP = {40: '==', 41: '!=', 42: '<', 43: '<=', 44: '>', 45: '>='}
MODES = {1: 'local', 2: 'local[]', 4: 'ptr[]', 8: 'localf', 16: 'localf[]', 32: 'ptrf[]'}

TABLES = {
    'event': [('src/game/editloop3.cpp', 'ext_func_info'), ('src/game/btsysscript.cpp', 'ext_func_info')],
    'monster': [('src/game/runscript_opcodes.cpp', 'ext_func_info')],
}


def ext_names(port, table):
    names = {}
    for rel, start in TABLES[table]:
        text = (port / rel).read_text(encoding='utf-8', errors='replace')
        at = text.find(start + '[]') if start + '[]' in text else text.find(start)
        end = text.find('};', at)
        for m in re.finditer(r'\{\s*(?:\.function\s*=\s*)?(_\w+)\s*,\s*(?:\.operation\s*=\s*)?(-?\d+)\s*\}',
                             text[at:end]):
            names[int(m.group(2))] = m.group(1).lstrip('_')
    return names


def string_at(data, off):
    end = data.find(b'\0', off)
    return data[off:end].decode('cp932', errors='replace')


class Script:
    def __init__(self, data):
        self.data = data
        self.unk, self.main, self.code, self.prog, self.prog_num = struct.unpack_from('<5i', data, 0)
        self.progs = [struct.unpack_from('<2i', data, self.prog + 8 * i) for i in range(self.prog_num)]

    def func(self, rec_off):
        addr, name, local, arg = struct.unpack_from('<iIii', self.data, rec_off)
        return addr, local, arg

    def insn(self, code_off):
        return struct.unpack_from('<3i', self.data, self.code + code_off)

    def function_end(self, addr):
        # A function runs until the next function's start; walk until a RET/END past every jump target.
        far = addr
        off = addr
        while self.code + off + 12 <= len(self.data):
            op, a1, a2 = self.insn(off)
            if op in (16, 17, 18) and a1 > far:
                far = a1
            if op in (15, 27) and off >= far:
                return off + 12
            off += 12
        return off


def disasm(script, rec, names, label, out, queue, seen):
    addr, local, arg = script.func(rec)
    out.append(f'\n== {label}: code+{addr:#x} args={arg} locals={local}')
    end = script.function_end(addr)
    targets = {script.insn(o)[1] for o in range(addr, end, 12) if script.insn(o)[0] in (16, 17, 18)}
    stack = []  # recent PUSH values for naming EXT calls
    for off in range(addr, end, 12):
        op, a1, a2 = script.insn(off)
        name = OPS.get(op, f'op{op}')
        mark = 'L' if off in targets else ' '
        if op == 3:
            if a1 == 1:
                text, val = f'PUSH {a2}', a2
            elif a1 == 2:
                f = struct.unpack('<f', struct.pack('<i', a2))[0]
                text, val = f'PUSH {f:g}f', f
            elif a1 == 3:
                s = string_at(script.data, script.code + a2)
                text, val = f'PUSH "{s}"', s
            else:
                text, val = f'PUSH ?{a1} {a2}', None
            stack.append(val)
        elif op in (1, 2):
            text = f'{name} {MODES.get(a2, a2)}[{a1}]'
            stack.append(None)
        elif op == 14:
            text = f'CMP {CMP.get(a1, a1)}'
            stack = stack[:-2] + [None]
        elif op in (16, 17, 18):
            text = f'{name} {a1:#x}'
            if op != 16:
                stack = stack[:-1]
        elif op == 19:
            callee = script.code + a2
            t_addr = script.func(callee)[0]
            text = f'CALL func@code+{t_addr:#x}'
            n_args = script.func(callee)[2]
            stack = (stack[:-n_args] if n_args else stack) + [None]
            if callee not in seen:
                seen.add(callee)
                queue.append((callee, f'func@code+{t_addr:#x}'))
        elif op == 21:
            argc = a1
            idx = stack[-argc] if len(stack) >= argc else None
            fname = names.get(idx, f'ext{idx}') if isinstance(idx, int) else '?'
            args = stack[-argc + 1:] if argc > 1 and len(stack) >= argc else []
            text = f'EXT {fname}({", ".join(repr(a) if a is not None else "_" for a in args)})  [argc {argc - 1}]'
            stack = stack[:-argc] if len(stack) >= argc else []
        elif op == 20:
            text = f'PRINT {a1}'
            stack = stack[:-a1] if a1 else stack
        else:
            text = name
            if op in (5, 6, 7, 8, 9, 10, 24, 25):
                stack = stack[:-2] + [None]
            elif op in (11, 12, 13, 26, 29, 30):
                stack = stack[:-1] + [None]
            elif op == 4:
                stack = stack[:-1]
        out.append(f'{mark}{off:#07x}  {text}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--table', default='event', choices=TABLES)
    ap.add_argument('--prog', type=int, nargs='*')
    ap.add_argument('--port', default='E:/Gauntlet-build/Chronicle/port')
    ap.add_argument('--list', action='store_true', help='only list the program numbers')
    a = ap.parse_args()
    data = Path(a.file).read_bytes()
    s = Script(data)
    if a.list:
        print(' '.join(str(no) for no, _ in s.progs))
        return
    names = ext_names(Path(a.port), a.table)
    out, queue, seen = [], [], set()
    want = s.progs if not a.prog else [p for p in s.progs if p[0] in a.prog]
    if not a.prog:
        queue.append((s.main, 'main'))
        seen.add(s.main)
    for no, rec in want:
        queue.append((rec, f'program {no}'))
        seen.add(rec)
    while queue:
        rec, label = queue.pop(0)
        disasm(s, rec, names, label, out, queue, seen)
    sys.stdout.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
