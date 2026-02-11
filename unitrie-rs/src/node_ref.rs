#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum NodeReferenceKind {
    Embedded,
    Hashed,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct NodeReference {
    kind: NodeReferenceKind,
    encoded_size: usize,
}

impl NodeReference {
    pub const HASH_REFERENCE_SIZE: usize = 32;

    pub fn embedded(encoded_size: usize) -> Self {
        Self {
            kind: NodeReferenceKind::Embedded,
            encoded_size,
        }
    }

    pub fn hashed() -> Self {
        Self {
            kind: NodeReferenceKind::Hashed,
            encoded_size: Self::HASH_REFERENCE_SIZE,
        }
    }

    pub fn encoded_size(self) -> usize {
        self.encoded_size
    }

    pub fn kind(self) -> NodeReferenceKind {
        self.kind
    }
}

#[cfg(test)]
mod tests {
    use super::{NodeReference, NodeReferenceKind};

    #[test]
    fn hashed_reference_uses_fixed_size() {
        let reference = NodeReference::hashed();
        assert_eq!(reference.kind(), NodeReferenceKind::Hashed);
        assert_eq!(reference.encoded_size(), NodeReference::HASH_REFERENCE_SIZE);
    }

    #[test]
    fn embedded_reference_uses_input_size() {
        let reference = NodeReference::embedded(19);
        assert_eq!(reference.kind(), NodeReferenceKind::Embedded);
        assert_eq!(reference.encoded_size(), 19);
    }
}
