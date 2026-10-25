"""Check the ABI export of cross-compiled Android libraries without executing them."""

import argparse
from pathlib import Path
import re
import subprocess


ARCHITECTURES = {
    "arm64-v8a": "aarch64-linux-android",
    "armeabi-v7a": "thumbv7a-linux-androideabi",
    "x86_64": "x86_64-linux-android",
}


def abi_from_disassembly(output):
    # The Rust export returns a constant. Reject unexpected code instead of
    # guessing an ABI from another instruction or merely finding its symbol.
    function = output.split("<cindel_abi_version>:")
    if len(function) != 2:
        raise RuntimeError("Missing or ambiguous cindel_abi_version export")
    instructions = []
    for line in function[1].splitlines():
        match = re.match(r"\s*[0-9a-fA-F]+:\s+(.+)", line)
        if not match:
            continue
        instruction = re.split(r"\s+//", match[1])[0].strip()
        instructions.append(instruction)
        if re.fullmatch(r"ret[q]?|bx\s+lr", instruction):
            break
    if len(instructions) != 2 or not re.fullmatch(r"ret[q]?|bx\s+lr", instructions[-1]):
        raise RuntimeError(f"Unexpected ABI export: {instructions}")
    value = re.fullmatch(
        r"(?:mov[l]?\s+\$(0x[0-9a-fA-F]+|[0-9]+),\s*%eax|"
        r"mov[s]?\s+(?:w0|r0),\s*#(0x[0-9a-fA-F]+|[0-9]+))",
        instructions[0],
    )
    if not value:
        raise RuntimeError(f"Unexpected ABI constant: {instructions[0]}")
    return int(next(group for group in value.groups() if group is not None), 0)


def verify(directory, objdump):
    for architecture, triple in ARCHITECTURES.items():
        library = directory / architecture / "libcindel_native.so"
        output = subprocess.check_output(
            [str(objdump), f"--triple={triple}",
             "--disassemble-symbols=cindel_abi_version", "--no-show-raw-insn", str(library)],
            text=True, timeout=60,
        )
        abi = abi_from_disassembly(output)
        if abi != 39:
            raise RuntimeError(f"{library}: expected ABI 39, received {abi}")
        print(f"PASS ABI 39: {library}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--objdump", type=Path, required=True)
    arguments = parser.parse_args()
    verify(arguments.directory, arguments.objdump)
