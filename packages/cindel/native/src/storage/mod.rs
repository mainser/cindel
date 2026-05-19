#[allow(dead_code)]
pub trait StorageEngine {
    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String>;
    fn put(&self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String>;
    fn delete(&self, collection: &str, id: u64) -> Result<(), String>;
}
