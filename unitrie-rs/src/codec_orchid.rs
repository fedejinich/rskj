#[derive(Debug, Clone, Copy, Default, Eq, PartialEq)]
pub struct OrchidCodec;

impl OrchidCodec {
    pub fn encode_node(payload: &[u8]) -> Vec<u8> {
        let mut encoded = Vec::with_capacity(1 + 4 + payload.len());
        encoded.push(0x00);
        encoded.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        encoded.extend_from_slice(payload);
        encoded
    }

    pub fn decode_node(payload: &[u8]) -> Vec<u8> {
        if payload.len() < 5 || payload[0] != 0x00 {
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
    use super::OrchidCodec;

    #[test]
    fn encode_decode_round_trip() {
        let payload = b"orchid-node";
        let encoded = OrchidCodec::encode_node(payload);
        let decoded = OrchidCodec::decode_node(&encoded);
        assert_eq!(decoded, payload);
    }

    #[test]
    fn decode_rejects_invalid_header() {
        let decoded = OrchidCodec::decode_node(&[0x01, 0, 0, 0, 1, 1]);
        assert!(decoded.is_empty());
    }
}
