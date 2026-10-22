#!/usr/bin/env python3
"""The file half of the toolchain contract (scripts/toolchain-contract.sh).

Reads a toolchain image's filesystem, exported as a tar whose root is what a
Harness sees at the mount directory, and checks that:

  - every file is readable, and every directory readable and searchable, by
    the uid the tools run as; every bin/ entry is a file it can execute;
  - no symlink leaves the prefix (an absolute target outside it, or a relative
    one above the image root);
  - no file names another /opt/kagent/tools/<other> prefix: the toolchain was
    built at its own mount directory, which its shebangs and library paths
    embed;
  - every dynamically linked ELF file finds each library it needs (DT_NEEDED)
    under the prefix.

Usage: toolchain-files.py <rootfs.tar> <prefix> <uid>
"""

import posixpath
import re
import struct
import sys
import tarfile

# What `docker export` adds to every container's filesystem.
DOCKER_ADDED = {".dockerenv", "etc/hosts", "etc/hostname", "etc/resolv.conf", "etc/mtab"}
DOCKER_ADDED_DIRS = ("dev", "proc", "sys")

PREFIX_RE = re.compile(rb"/opt/kagent/tools/([a-z0-9][a-z0-9-]*)")

PT_LOAD, PT_DYNAMIC = 1, 2
DT_NULL, DT_NEEDED, DT_STRTAB = 0, 1, 5

failures = []


def fail(msg):
    failures.append(msg)
    print(f"FAIL  {msg}")


def docker_added(path):
    return path in DOCKER_ADDED or any(
        path == d or path.startswith(d + "/") for d in DOCKER_ADDED_DIRS
    )


def can(member, uid, bits):
    """Whether uid holds every permission in bits (r=4, w=2, x=1)."""
    mode = member.mode
    if member.uid == uid:
        have = (mode >> 6) & 7
    elif member.gid == uid:
        have = (mode >> 3) & 7
    else:
        have = mode & 7
    return have & bits == bits


def needed_libraries(data):
    """The DT_NEEDED names of an ELF file, or None if it is not dynamic ELF."""
    if len(data) < 64 or data[:4] != b"\x7fELF":
        return None
    is64 = data[4] == 2
    end = "<" if data[5] == 1 else ">"
    try:
        if is64:
            phoff, = struct.unpack_from(end + "Q", data, 0x20)
            phentsize, phnum = struct.unpack_from(end + "HH", data, 0x36)
            ph_fmt, dyn_fmt = end + "IIQQQQQQ", end + "qQ"
        else:
            phoff, = struct.unpack_from(end + "I", data, 0x1C)
            phentsize, phnum = struct.unpack_from(end + "HH", data, 0x2A)
            ph_fmt, dyn_fmt = end + "IIIIIIII", end + "iI"
        loads, dynamic = [], None
        for i in range(phnum):
            fields = struct.unpack_from(ph_fmt, data, phoff + i * phentsize)
            if is64:
                p_type, _, p_offset, p_vaddr, _, p_filesz, _, _ = fields
            else:
                p_type, p_offset, p_vaddr, _, p_filesz, _, _, _ = fields
            if p_type == PT_LOAD:
                loads.append((p_vaddr, p_offset, p_filesz))
            elif p_type == PT_DYNAMIC:
                dynamic = (p_offset, p_filesz)
        if dynamic is None:
            return None

        def offset(vaddr):
            for start, off, size in loads:
                if start <= vaddr < start + size:
                    return off + vaddr - start
            return None

        entries, strtab = [], None
        size = struct.calcsize(dyn_fmt)
        for pos in range(dynamic[0], dynamic[0] + dynamic[1], size):
            tag, val = struct.unpack_from(dyn_fmt, data, pos)
            if tag == DT_NULL:
                break
            if tag == DT_STRTAB:
                strtab = offset(val)
            entries.append((tag, val))
        if strtab is None:
            return []
        names = []
        for tag, val in entries:
            if tag == DT_NEEDED:
                start = strtab + val
                names.append(data[start:data.index(b"\0", start)].decode())
        return names
    except (struct.error, ValueError):
        return None


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    archive, prefix, uid = sys.argv[1], sys.argv[2].rstrip("/"), int(sys.argv[3])
    name = posixpath.basename(prefix).encode()

    with tarfile.open(archive) as tar:
        members = {}
        for m in tar.getmembers():
            path = posixpath.normpath(m.name.lstrip("/"))
            if path != "." and not docker_added(path):
                members[path] = m

        def resolve(path, depth=0):
            """The member a path names inside the image, symlinks followed."""
            m = members.get(path)
            if m is None or not m.issym() or depth > 40:
                return m
            target = m.linkname
            if target.startswith("/"):
                if not target.startswith(prefix + "/"):
                    return None
                target = target[len(prefix) + 1:]
            else:
                target = posixpath.join(posixpath.dirname(path), target)
            return resolve(posixpath.normpath(target), depth + 1)

        basenames = {posixpath.basename(p) for p, m in members.items() if not m.isdir()}
        unreadable, others, libraries, checked = [], {}, [], 0

        for path, m in sorted(members.items()):
            if m.isdir():
                if not can(m, uid, 4 | 1):
                    unreadable.append(path + "/")
                continue
            if m.issym():
                target = m.linkname
                if target.startswith("/"):
                    leaves = not target.startswith(prefix + "/")
                else:
                    leaves = posixpath.normpath(
                        posixpath.join(posixpath.dirname(path), target)
                    ).startswith("..")
                if leaves:
                    fail(f"symlink {path} -> {target} leaves the prefix {prefix}")
                continue
            if not (m.isfile() or m.islnk()):
                fail(f"{path}: not a regular file, directory or symlink")
                continue
            if not can(m, uid, 4):
                unreadable.append(path)
            data = tar.extractfile(m).read() if m.isfile() else b""
            checked += 1
            for other in set(PREFIX_RE.findall(data)) - {name}:
                others.setdefault(other.decode(), []).append(path)
            needed = needed_libraries(data)
            for lib in needed or []:
                if lib not in basenames:
                    libraries.append(f"{path} needs {lib}")

        if unreadable:
            fail(f"uid {uid} cannot read {len(unreadable)} path(s): {', '.join(unreadable[:5])}")
        for other, paths in sorted(others.items()):
            fail(
                f"built at another prefix: {len(paths)} file(s) name "
                f"/opt/kagent/tools/{other}, e.g. {', '.join(paths[:3])}"
            )
        for line in libraries:
            fail(f"library not under the prefix: {line}")

        tools = [p for p in members if posixpath.dirname(p) == "bin"]
        if not tools:
            fail("bin/: no tools at the image root's bin/")
        for path in sorted(tools):
            target = resolve(path)
            if target is None or not (target.isfile() or target.islnk()):
                fail(f"{path}: does not resolve to a file under the prefix")
            elif not can(target, uid, 4 | 1):
                fail(f"{path}: uid {uid} cannot execute it")

    if not failures:
        print(
            f"ok    files: {checked} files readable by uid {uid}, {len(tools)} tool(s) "
            f"in bin/ executable, built at {prefix}, every library under the prefix"
        )
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
