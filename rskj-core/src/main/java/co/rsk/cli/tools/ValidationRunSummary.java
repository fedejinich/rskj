/*
 * This file is part of RskJ
 * Copyright (C) 2026 RSK Labs Ltd.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
package co.rsk.cli.tools;

final class ValidationRunSummary {
    private final int attemptIndex;
    private final long fromBlock;
    private final long toBlock;
    private final int blockCount;
    private final int processedBlocks;
    private final int divergenceCount;
    private final int rustExceptionsCount;
    private final long javaNanos;
    private final long rustNanos;

    ValidationRunSummary(
            int attemptIndex,
            long fromBlock,
            long toBlock,
            int blockCount,
            int processedBlocks,
            int divergenceCount,
            int rustExceptionsCount,
            long javaNanos,
            long rustNanos) {
        this.attemptIndex = attemptIndex;
        this.fromBlock = fromBlock;
        this.toBlock = toBlock;
        this.blockCount = blockCount;
        this.processedBlocks = processedBlocks;
        this.divergenceCount = divergenceCount;
        this.rustExceptionsCount = rustExceptionsCount;
        this.javaNanos = javaNanos;
        this.rustNanos = rustNanos;
    }

    int getAttemptIndex() {
        return attemptIndex;
    }

    long getFromBlock() {
        return fromBlock;
    }

    long getToBlock() {
        return toBlock;
    }

    int getBlockCount() {
        return blockCount;
    }

    int getProcessedBlocks() {
        return processedBlocks;
    }

    int getDivergenceCount() {
        return divergenceCount;
    }

    int getRustExceptionsCount() {
        return rustExceptionsCount;
    }

    long getJavaNanos() {
        return javaNanos;
    }

    long getRustNanos() {
        return rustNanos;
    }

    boolean isSuccessful() {
        return divergenceCount == 0 && rustExceptionsCount == 0 && processedBlocks == blockCount;
    }
}
