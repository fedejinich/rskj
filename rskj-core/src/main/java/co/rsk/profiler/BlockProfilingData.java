package co.rsk.profiler;

import java.time.Instant;

import org.ethereum.util.ByteUtil;

public class BlockProfilingData {
    public static enum Phase {
        // block is anounced via NEW_BLOCK_HASHES (there's another method NEW_BLOCK_HASH but it seems deprectaded)
        ANOUNCEMENT,
        // block is received via BLOCK_MESSAGE
        PROCESSING_START,
        // it goes through some light validations
        VALIDATION_BLOCK_HEADER,
        VALIDATION_BLOCK_CONTAINED,
        VALIDATION_PREPROCESS_START,
        VALIDATION_PREPROCESS_END,
        // and it's broadcasted if everything it's ok
        BROADCASTED,
        // then the block it's fully processed (async or sync) and, if everything it's ok, it's connected to the blockchain
        PROCESSING_ASYNC,
        PROCESSING_SYNC,
        PROCESSING_END,
        PROCESSING_REJECTED,
    }

    private byte[] blockHash;
    private Phase phase;
    private long instant;

    public BlockProfilingData(byte[] blockHash, Phase phase) {
        this.blockHash = blockHash;
        this.phase = phase;
        this.instant = Instant.now().toEpochMilli();
    }

    @Override
    public String toString() {
        // instant,blockHash,phase
        return String.format("%d,%s,%s", instant, ByteUtil.toHexString(blockHash), phase);
    }
}
