package co.rsk.profiler;

import java.time.Instant;

import org.ethereum.util.ByteUtil;

public class BlockProfilingData {
    public static enum Phase { ANOUNCEMENT, PROCESSING_START, PROCESSING_END, BROADCASTED }

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
