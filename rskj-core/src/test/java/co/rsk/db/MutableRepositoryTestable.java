package co.rsk.db;

import co.rsk.trie.MutableTrie;
import org.ethereum.db.MutableRepository;
import org.ethereum.db.OperationType;

import static org.ethereum.db.OperationType.READ_OPERATION;
import static org.ethereum.db.OperationType.WRITE_OPERATION;

public class MutableRepositoryTestable extends MutableRepository {
    public MutableRepositoryTestable(MutableTrie mutableTrie,
                                     MutableRepository parentRepository, boolean enableTracking) {
        super(mutableTrie, parentRepository, enableTracking);
    }

    public static MutableRepositoryTestable trackedRepository(MutableTrie mutableTrie) {
        return new MutableRepositoryTestable(mutableTrie, null, true);
    }

    public void trackNode(byte[] key, OperationType operationType, boolean isSuccessful) {
        super.trackNode(key, operationType, isSuccessful);
    }

    public void trackNodeWriteOperation(byte[] key) {
        super.trackNode(key, WRITE_OPERATION, true);
    }

    public void trackNodeReadOperation(byte[] key, boolean result) {
        super.trackNode(key, READ_OPERATION, result);
    }
}
