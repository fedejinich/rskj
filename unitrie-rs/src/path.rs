pub fn calculate_encoded_length(key_length: usize) -> usize {
    key_length / 8 + usize::from(key_length % 8 != 0)
}

pub fn encode(path: &[u8]) -> Vec<u8> {
    let mut encoded = vec![0u8; calculate_encoded_length(path.len())];
    for (idx, bit) in path.iter().enumerate() {
        if *bit == 0 {
            continue;
        }
        let byte_index = idx / 8;
        let offset = idx % 8;
        encoded[byte_index] |= 0x80 >> offset;
    }
    encoded
}

pub fn decode(encoded: &[u8], bit_length: usize) -> Vec<u8> {
    let mut path = vec![0u8; bit_length];
    for idx in 0..bit_length {
        let byte_index = idx / 8;
        let offset = idx % 8;
        if ((encoded[byte_index] >> (7 - offset)) & 0x01) != 0 {
            path[idx] = 1;
        }
    }
    path
}

#[cfg(test)]
mod tests {
    use super::{decode, encode};

    #[test]
    fn round_trip() {
        let path = vec![1, 0, 1, 1, 0, 0, 1, 0, 1];
        let encoded = encode(&path);
        let decoded = decode(&encoded, path.len());
        assert_eq!(decoded, path);
    }
}
