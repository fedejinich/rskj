#[derive(Debug, Clone, Copy, Default, Eq, PartialEq)]
pub struct Rskip107Codec;

impl Rskip107Codec {
    pub fn encode_node(payload: &[u8]) -> Vec<u8> {
        let mut encoded = Vec::with_capacity(1 + 4 + payload.len());
        encoded.push(0x01);
        encoded.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        encoded.extend_from_slice(payload);
        encoded
    }

    pub fn decode_node(payload: &[u8]) -> Vec<u8> {
        if payload.len() < 5 || payload[0] != 0x01 {
            return Vec::new();
        }

        let mut length_bytes = [0u8; 4];
        length_bytes.copy_from_slice(&payload[1..5]);
        let declared_length = u32::from_be_bytes(length_bytes) as usize;
        if payload.len() != 5 + declared_length {
            return Vec::new();
        }

        payload[5..].to_vec()
    }
}

#[cfg(test)]
mod tests {
    use super::Rskip107Codec;

    #[test]
    fn encode_decode_round_trip() {
        let payload = b"node-payload";
        let encoded = Rskip107Codec::encode_node(payload);
        let decoded = Rskip107Codec::decode_node(&encoded);
        assert_eq!(decoded, payload);
    }

    #[test]
    fn decode_rejects_invalid_header() {
        let decoded = Rskip107Codec::decode_node(&[0xff, 0, 0, 0, 1, 1]);
        assert!(decoded.is_empty());
    }
}
