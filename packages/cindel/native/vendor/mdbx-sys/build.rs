use bindgen::{
    callbacks::{IntKind, ParseCallbacks},
    Formatter,
};
use std::{
    env, fs,
    path::{Path, PathBuf},
};

#[derive(Debug)]
struct Callbacks;

impl ParseCallbacks for Callbacks {
    fn int_macro(&self, name: &str, _value: i64) -> Option<IntKind> {
        match name {
            "MDBX_SUCCESS"
            | "MDBX_KEYEXIST"
            | "MDBX_NOTFOUND"
            | "MDBX_PAGE_NOTFOUND"
            | "MDBX_CORRUPTED"
            | "MDBX_PANIC"
            | "MDBX_VERSION_MISMATCH"
            | "MDBX_INVALID"
            | "MDBX_MAP_FULL"
            | "MDBX_DBS_FULL"
            | "MDBX_READERS_FULL"
            | "MDBX_TLS_FULL"
            | "MDBX_TXN_FULL"
            | "MDBX_CURSOR_FULL"
            | "MDBX_PAGE_FULL"
            | "MDBX_MAP_RESIZED"
            | "MDBX_INCOMPATIBLE"
            | "MDBX_BAD_RSLOT"
            | "MDBX_BAD_TXN"
            | "MDBX_BAD_VALSIZE"
            | "MDBX_BAD_DBI"
            | "MDBX_LOG_DONTCHANGE"
            | "MDBX_DBG_DONTCHANGE"
            | "MDBX_RESULT_TRUE"
            | "MDBX_UNABLE_EXTEND_MAPSIZE"
            | "MDBX_PROBLEM"
            | "MDBX_LAST_LMDB_ERRCODE"
            | "MDBX_BUSY"
            | "MDBX_EMULTIVAL"
            | "MDBX_EBADSIGN"
            | "MDBX_WANNA_RECOVERY"
            | "MDBX_EKEYMISMATCH"
            | "MDBX_TOO_LARGE"
            | "MDBX_THREAD_MISMATCH"
            | "MDBX_TXN_OVERLAPPING"
            | "MDBX_BACKLOG_DEPLETED"
            | "MDBX_DUPLICATED_CLK"
            | "MDBX_DANGLING_DBI"
            | "MDBX_OUSTED"
            | "MDBX_MVCC_RETARDED"
            | "MDBX_LAST_ERRCODE" => Some(IntKind::Int),
            _ => Some(IntKind::UInt),
        }
    }
}

fn add_existing_path(paths: &mut Vec<PathBuf>, path: PathBuf) {
    if path.exists() && !paths.iter().any(|existing| existing == &path) {
        paths.push(path);
    }
}

fn latest_child_dir(path: &Path) -> Option<PathBuf> {
    let mut dirs = fs::read_dir(path)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    dirs.sort();
    dirs.pop()
}

fn add_windows_sdk_includes(paths: &mut Vec<PathBuf>, root: PathBuf, version: Option<String>) {
    let include_root = root.join("Include");
    let version_dir = version
        .map(|version| include_root.join(version.trim_end_matches('\\')))
        .filter(|path| path.exists())
        .or_else(|| latest_child_dir(&include_root));

    if let Some(version_dir) = version_dir {
        for name in ["ucrt", "shared", "um", "winrt"] {
            add_existing_path(paths, version_dir.join(name));
        }
    }
}

fn find_visual_studio_includes(paths: &mut Vec<PathBuf>, root: &Path) {
    let Ok(editions) = fs::read_dir(root) else {
        return;
    };

    for edition in editions.filter_map(Result::ok).map(|entry| entry.path()) {
        let Ok(instances) = fs::read_dir(edition) else {
            continue;
        };

        for instance in instances.filter_map(Result::ok).map(|entry| entry.path()) {
            let msvc_root = instance.join("VC").join("Tools").join("MSVC");
            if let Some(version_dir) = latest_child_dir(&msvc_root) {
                add_existing_path(paths, version_dir.join("include"));
            }
        }
    }
}

fn windows_bindgen_include_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    if let Some(include) = env::var_os("INCLUDE") {
        for path in env::split_paths(&include) {
            add_existing_path(&mut paths, path);
        }
    }

    if let Ok(vctools) = env::var("VCToolsInstallDir") {
        add_existing_path(&mut paths, PathBuf::from(vctools).join("include"));
    }

    let sdk_version = env::var("WindowsSDKVersion").ok();
    if let Ok(sdk_dir) = env::var("WindowsSdkDir") {
        add_windows_sdk_includes(&mut paths, PathBuf::from(sdk_dir), sdk_version.clone());
    }

    add_windows_sdk_includes(
        &mut paths,
        PathBuf::from(r"C:\Program Files (x86)\Windows Kits\10"),
        sdk_version,
    );

    find_visual_studio_includes(
        &mut paths,
        Path::new(r"C:\Program Files\Microsoft Visual Studio"),
    );
    find_visual_studio_includes(
        &mut paths,
        Path::new(r"C:\Program Files (x86)\Microsoft Visual Studio"),
    );

    paths
}

fn main() {
    let target = env::var("TARGET").unwrap();
    let mut mdbx = PathBuf::from(&env::var("CARGO_MANIFEST_DIR").unwrap());
    mdbx.push("libmdbx");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());

    let mut bindings = bindgen::Builder::default()
        .header(mdbx.join("mdbx.h").to_string_lossy())
        .allowlist_var("^(MDBX|mdbx)_.*")
        .allowlist_type("^(MDBX|mdbx)_.*")
        .allowlist_function("^(MDBX|mdbx)_.*")
        .size_t_is_usize(true)
        .ctypes_prefix("::libc")
        .parse_callbacks(Box::new(Callbacks))
        .layout_tests(false)
        .prepend_enum_name(false)
        .generate_comments(false)
        .disable_header_comment()
        .formatter(Formatter::None)
        .clang_arg(format!("--target={target}"));

    if target.contains("windows") {
        bindings = bindings
            .clang_arg("-D_WIN32_WINNT=0x0600")
            .clang_arg("-DWIN32")
            .clang_arg("-D_WIN32")
            .clang_arg("-D_WINDOWS")
            .clang_arg("-fms-extensions")
            .clang_arg("-fdeclspec");

        for include_path in windows_bindgen_include_paths() {
            bindings = bindings
                .clang_arg("-isystem")
                .clang_arg(include_path.to_string_lossy().into_owned());
        }
    }

    if target.contains("android") {
        // Android's system `struct iovec` exposes `iov_len` through a platform
        // typedef that bindgen emits as `u64` on 64-bit targets. The safe
        // `libmdbx` wrapper expects the MDBX value length to be Rust `usize`,
        // matching libmdbx's own custom value struct layout.
        bindings = bindings.clang_arg("-D__sun");
    }

    let bindings = bindings.generate().expect("Unable to generate bindings");

    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");

    let mut mdbx = PathBuf::from(&env::var("CARGO_MANIFEST_DIR").unwrap());
    mdbx.push("libmdbx");

    let mut cc_builder = cc::Build::new();
    cc_builder
        .flag_if_supported("-Wall")
        .flag_if_supported("-Werror")
        .flag_if_supported("-ffunction-sections")
        .flag_if_supported("-fvisibility=hidden")
        .flag_if_supported("-Wno-error=attributes");

    if cfg!(debug_assertions) {
        cc_builder.define("MDBX_FORCE_ASSERTIONS", "1");
    } else {
        cc_builder.define("NDEBUG", "1");
    }

    cc_builder
        .define("MDBX_BUILD_CXX", "0")
        .define("MDBX_BUILD_TOOLS", "0")
        .define("MDBX_BUILD_SHARED_LIBRARY", "0")
        .define("MDBX_TXN_CHECKOWNER", "0");

    if target.contains("windows") {
        cc_builder
            .define("MDBX_LOCK_SUFFIX", "L\".lock\"")
            .define("_WIN32_WINNT", "0x0600")
            .define("MDBX_WITHOUT_MSVC_CRT", "1")
            .define("UNICODE", "1")
            .define("HAVE_LIBM", "1");
    } else {
        cc_builder.define("MDBX_LOCK_SUFFIX", "\".lock\"");
    }

    // Keep libmdbx CPU dispatch conservative across Android/Linux builds, matching
    // Isar's performance-oriented build profile and avoiding target-specific probes.
    if target.ends_with("-musl") || target.contains("android") || target.contains("linux") {
        cc_builder.define("MDBX_HAVE_BUILTIN_CPU_SUPPORTS", "0");
    }

    if target.contains("apple") {
        cc_builder.define("MDBX_APPLE_SPEED_INSTEADOF_DURABILITY", "1");
    }

    if target.contains("apple-ios") {
        cc_builder.flag_if_supported("-fno-stack-check");
    }

    let cflags = cc_builder.get_compiler().cflags_env();
    cc_builder.define("MDBX_BUILD_FLAGS", format!("{:?}", cflags).as_str());

    if target.contains("windows") {
        println!(r"cargo:rustc-link-lib=dylib=ntdll");
        println!(r"cargo:rustc-link-lib=dylib=user32");
        println!(r"cargo:rustc-link-lib=dylib=kernel32");
        println!(r"cargo:rustc-link-lib=dylib=advapi32");
        println!(r"cargo:rustc-link-lib=dylib=ole32");
        println!(r"cargo:rustc-link-lib=dylib=psapi");
    }

    cc_builder.file(mdbx.join("mdbx.c")).compile("libmdbx.a");
}
