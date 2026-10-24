use super::*;

#[test]
fn nullable_string_list_can_be_the_first_field_in_both_writer_modes() {
    for native in [false, true] {
        let mut writer = CindelNativeBatchWriter::new(&[4], 1, native).unwrap();
        let mut list = writer.begin_list(0, 2).unwrap();
        list.write_typed_bytes(0, b"a", NativeValueKind::String).unwrap();
        list.write_null(1).unwrap();
        writer.end_list(list).unwrap();
        writer.save_document(1).unwrap();
    }
}

#[test]
fn json_string_list_reader_preserves_unicode_escapes_null_and_empty() {
    let list = parse_native_raw_list(br#"["a\n\"b",null,"","\uD83D\uDE80"]"#).unwrap();
    assert_eq!(list.entries.len(), 4);
    assert!(list.entries[1].is_null);
    assert_eq!(list.entries[2].payload_len, 0);
    let entry = &list.entries[3];
    assert_eq!(&list.bytes[entry.payload_start..entry.payload_start + entry.payload_len], "🚀".as_bytes());
}

#[test]
fn generic_list_count_is_not_a_json_marker() {
    let bytes = crate::document_format::write_list(&vec![Some(BinaryValue::Int(1)); 91]).unwrap();
    assert_eq!(bytes[0], b'[');
    let list = parse_native_raw_list(&bytes).unwrap();
    assert_eq!(list.entries.len(), 91);
}

#[test]
fn json_list_reader_retains_only_the_current_list() {
    // The converted representation is linear in this list, not in collection
    // size; repeated readers are dropped instead of cached across documents.
    let count = 4096;
    let payload = format!("[{}]", vec!["\"abcd\""; count].join(","));
    for _ in 0..100 {
        let list = parse_native_raw_list(payload.as_bytes()).unwrap();
        assert_eq!(list.entries.len(), count);
        assert_eq!(list.bytes.len(), 4 + count * (8 + 4));
        assert!(list.bytes.capacity() <= 2 * list.bytes.len());
        assert!(list.entries.capacity() <= 2 * count);
    }
}
