#[cfg(test)]
struct MdbxBuildProbe;

#[cfg(test)]
impl MdbxBuildProbe {
    fn open(directory: impl AsRef<std::path::Path>) -> Result<(), String> {
        use libmdbx::{Database, NoWriteMap};

        let directory = directory.as_ref();
        std::fs::create_dir_all(directory).map_err(|error| error.to_string())?;

        let database =
            Database::<NoWriteMap>::open(directory).map_err(|error| error.to_string())?;
        database.info().map_err(|error| error.to_string())?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opens_mdbx_database_directory() {
        // Scenario: The optional MDBX dependency is enabled for a native build.
        // Covers:
        // - Compiling the `libmdbx` crate behind Cindel's `mdbx` feature.
        // - Opening an MDBX environment with the Windows-compatible default mode.
        // Expected: The probe opens the database directory without becoming the
        //   default Cindel backend.
        let directory =
            std::env::temp_dir().join(format!("cindel_mdbx_probe_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&directory);

        let result = MdbxBuildProbe::open(&directory);

        assert!(result.is_ok(), "{:?}", result.err());
        assert!(directory.exists());

        let _ = std::fs::remove_dir_all(&directory);
    }
}
