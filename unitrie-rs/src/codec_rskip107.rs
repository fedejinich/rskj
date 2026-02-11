#[derive(Debug, Clone, Copy, Default, Eq, PartialEq)]
pub struct Rskip107Codec;

impl Rskip107Codec {
    pub fn encode_node(_payload: &[u8]) -> Vec<u8> {
        Vec::new()
    }

    pub fn decode_node(_payload: &[u8]) -> Vec<u8> {
        Vec::new()
    }
}
