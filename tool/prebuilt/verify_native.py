"""Smoke-check the exact release library, without loader fallback paths."""

import argparse
import ctypes
import platform
from pathlib import Path
import tempfile


def verify(library_path: Path) -> None:
    library_path = library_path.resolve(strict=True)
    library = ctypes.CDLL(str(library_path))

    def bind(name, result, *arguments):
        function = getattr(library, name)
        function.restype = result
        function.argtypes = list(arguments)
        return function

    abi = bind("cindel_abi_version", ctypes.c_uint32)()
    if abi != 39:
        raise RuntimeError(f"{library_path}: expected ABI 39, received {abi}")

    open_database = bind(
        "cindel_open_with_backend",
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_int32),
    )
    close_database = bind("cindel_close", None, ctypes.c_void_p)
    take_error = bind(
        "cindel_take_error",
        ctypes.c_void_p,
        ctypes.c_int32,
        ctypes.POINTER(ctypes.c_size_t),
    )
    free_buffer = bind("cindel_free_buffer", None, ctypes.c_void_p, ctypes.c_size_t)

    def diagnostic(status):
        length = ctypes.c_size_t()
        pointer = take_error(status, ctypes.byref(length))
        if not pointer:
            return f"status {status} without a diagnostic"
        try:
            return ctypes.string_at(pointer, length.value).decode("utf-8")
        finally:
            free_buffer(pointer, length.value)

    # Native release packages promise both engines. Reopen each database after
    # closure to catch a library that loads but cannot release its resources.
    for backend, name in ((0, "SQLite"), (1, "MDBX")):
        with tempfile.TemporaryDirectory(prefix="cindel-release-") as directory:
            encoded = directory.encode("utf-8")
            for attempt in ("open", "reopen"):
                status = ctypes.c_int32(-1)
                handle = open_database(
                    encoded, len(encoded), backend, ctypes.byref(status)
                )
                try:
                    if not handle or status.value != 0:
                        raise RuntimeError(
                            f"{name} {attempt} failed: {diagnostic(status.value)}"
                        )
                finally:
                    if handle:
                        close_database(handle)
        print(f"PASS {name}: open, close, reopen, close")
    print(f"PASS ABI 39: {library_path} ({platform.system()} {platform.machine()})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    verify(parser.parse_args().library)
