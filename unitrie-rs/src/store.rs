pub trait RawStore {
    fn save_raw_node(&mut self, _hash: &[u8], _serialized_node: &[u8]);
    fn save_raw_value(&mut self, _hash: &[u8], _value: &[u8]);
}
