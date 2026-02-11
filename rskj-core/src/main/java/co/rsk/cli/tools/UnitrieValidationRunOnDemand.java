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

import co.rsk.cli.PicoCliToolRskContextAware;
import co.rsk.core.bc.BlockExecutor;
import co.rsk.core.bc.BlockResult;
import co.rsk.db.RepositoryLocator;
import co.rsk.trie.engine.MutableTrieFactory;
import co.rsk.trie.engine.TrieEngineType;
import org.ethereum.core.Block;
import org.ethereum.db.BlockStore;
import org.ethereum.util.ByteUtil;
import picocli.CommandLine;

import javax.annotation.Nullable;
import java.io.IOException;
import java.lang.invoke.MethodHandles;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;

@CommandLine.Command(
        name = "unitrie-validation-run",
        mixinStandardHelpOptions = true,
        version = "unitrie-validation-run 1.0",
        description = "Validation Run (On-Demand) for Java vs Rust Unitrie parity"
)
public class UnitrieValidationRunOnDemand extends PicoCliToolRskContextAware {

    private static final DateTimeFormatter RUN_TIMESTAMP_FORMATTER =
            DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").withZone(ZoneOffset.UTC);

    @CommandLine.Option(names = {"-fb", "--fromBlock"}, description = "First block number to validate", required = true)
    private long fromBlock;

    @CommandLine.Option(
            names = {"-bc", "--blockCount"},
            description = "Number of blocks to validate (fast default for local runs)",
            defaultValue = "-1"
    )
    private int blockCount;

    @CommandLine.Option(
            names = {"--deep"},
            description = "Use deep validation profile, overriding --blockCount",
            defaultValue = "false"
    )
    private boolean deepProfile;

    @CommandLine.Option(
            names = {"--failFast"},
            description = "Stop at first divergence and return non-zero exit code",
            defaultValue = "true"
    )
    private boolean failFast;

    @CommandLine.Option(
            names = {"--rustLibraryPath"},
            description = "Optional absolute path to unitrie-rs native library"
    )
    @Nullable
    private String rustLibraryPath;

    @CommandLine.Option(
            names = {"--reportDir"},
            description = "Directory where validation artifacts are written",
            defaultValue = "build/reports/unitrie-validation"
    )
    private Path reportDir;

    public static void main(String[] args) {
        create(MethodHandles.lookup().lookupClass()).execute(args);
    }

    @Override
    public Integer call() throws IOException {
        int defaultFastBlockCount = ctx.getRskSystemProperties().getUnitrieValidationRunDefaultBlockCount();
        int defaultDeepBlockCount = ctx.getRskSystemProperties().getUnitrieValidationRunDeepBlockCount();

        int effectiveBlockCount;
        if (deepProfile) {
            effectiveBlockCount = defaultDeepBlockCount;
        } else if (blockCount > 0) {
            effectiveBlockCount = blockCount;
        } else {
            effectiveBlockCount = defaultFastBlockCount;
        }

        if (effectiveBlockCount <= 0) {
            printError("blockCount must be greater than zero");
            return 1;
        }

        long toBlock = fromBlock + effectiveBlockCount - 1L;
        printInfo(
                "Starting Validation Run (On-Demand): fromBlock={} toBlock={} blockCount={} profile={}",
                fromBlock,
                toBlock,
                effectiveBlockCount,
                deepProfile ? "deep" : "fast"
        );

        BlockStore blockStore = ctx.getBlockStore();
        BlockExecutor javaExecutor = buildExecutor(TrieEngineType.JAVA, true, null);
        BlockExecutor rustExecutor = buildExecutor(TrieEngineType.RUST, true, rustLibraryPath);

        long javaNanos = 0L;
        long rustNanos = 0L;
        int processedBlocks = 0;

        for (long blockNumber = fromBlock; blockNumber <= toBlock; blockNumber++) {
            Block block = blockStore.getChainBlockByNumber(blockNumber);
            if (block == null) {
                printError("Block {} not found in chain", blockNumber);
                return 1;
            }

            Block parent = blockStore.getBlockByHash(block.getParentHash().getBytes());
            if (parent == null) {
                printError("Parent block not found for block {}", blockNumber);
                return 1;
            }

            long javaStart = System.nanoTime();
            BlockResult javaResult = javaExecutor.execute(null, 0, block, parent.getHeader(), false, false, false);
            javaNanos += System.nanoTime() - javaStart;

            long rustStart = System.nanoTime();
            BlockResult rustResult;
            try {
                rustResult = rustExecutor.execute(null, 0, block, parent.getHeader(), false, false, false);
            } catch (RuntimeException ex) {
                Path artifactPath = writeFailureArtifact(
                        block,
                        null,
                        null,
                        "Rust execution failed with exception: " + ex.getMessage()
                );
                printError("Rust execution failed at block {}. Artifact: {}", blockNumber, artifactPath);
                return 1;
            }
            rustNanos += System.nanoTime() - rustStart;

            byte[] javaRoot = javaResult.getFinalState().getHash().getBytes();
            byte[] rustRoot = rustResult.getFinalState().getHash().getBytes();

            if (!Arrays.equals(javaRoot, rustRoot)) {
                Path artifactPath = writeFailureArtifact(
                        block,
                        javaRoot,
                        rustRoot,
                        "State root divergence detected between Java and Rust engines"
                );

                printError(
                        "Mismatch at block {} javaRoot={} rustRoot={} artifact={}",
                        blockNumber,
                        ByteUtil.toHexString(javaRoot),
                        ByteUtil.toHexString(rustRoot),
                        artifactPath
                );

                if (failFast) {
                    return 1;
                }
            }

            processedBlocks++;
        }

        printMetrics("java", javaNanos, processedBlocks);
        printMetrics("rust", rustNanos, processedBlocks);
        printInfo("Validation Run (On-Demand) completed successfully for {} blocks", processedBlocks);
        return 0;
    }

    private BlockExecutor buildExecutor(
            TrieEngineType engineType,
            boolean failOnMismatch,
            @Nullable String libraryPath) {
        MutableTrieFactory mutableTrieFactory = new MutableTrieFactory(engineType, failOnMismatch, libraryPath);
        RepositoryLocator repositoryLocator = new RepositoryLocator(
                ctx.getTrieStore(),
                ctx.getStateRootHandler(),
                mutableTrieFactory
        );

        return new BlockExecutor(repositoryLocator, ctx.getTransactionExecutorFactory(), ctx.getRskSystemProperties());
    }

    private Path writeFailureArtifact(
            Block block,
            @Nullable byte[] javaRoot,
            @Nullable byte[] rustRoot,
            String reason) throws IOException {
        String timestamp = RUN_TIMESTAMP_FORMATTER.format(Instant.now());
        Path runDir = reportDir.resolve("run-" + timestamp);
        Files.createDirectories(runDir);

        Path artifactPath = runDir.resolve("mismatch-block-" + block.getNumber() + ".txt");
        StringBuilder content = new StringBuilder();
        content.append("reason=").append(reason).append('\n');
        content.append("block.number=").append(block.getNumber()).append('\n');
        content.append("block.hash=").append(block.getHash().toHexString()).append('\n');
        content.append("block.parentHash=").append(block.getParentHash().toHexString()).append('\n');
        content.append("block.stateRoot=").append(ByteUtil.toHexString(block.getStateRoot())).append('\n');
        content.append("java.root=").append(nullableHex(javaRoot)).append('\n');
        content.append("rust.root=").append(nullableHex(rustRoot)).append('\n');

        Files.writeString(artifactPath, content.toString(), StandardCharsets.UTF_8);
        return artifactPath;
    }

    private static String nullableHex(@Nullable byte[] value) {
        return value == null ? "null" : ByteUtil.toHexString(value);
    }

    private static void printMetrics(String label, long totalNanos, int processedBlocks) {
        double totalMillis = totalNanos / 1_000_000.0;
        double millisPerBlock = processedBlocks == 0 ? 0.0 : totalMillis / processedBlocks;
        double blocksPerSecond = totalNanos == 0 ? 0.0 : (processedBlocks * 1_000_000_000.0) / totalNanos;

        printInfo(
                "engine={} blocks={} totalMs={} msPerBlock={} blocksPerSecond={}",
                label,
                processedBlocks,
                String.format("%.2f", totalMillis),
                String.format("%.2f", millisPerBlock),
                String.format("%.2f", blocksPerSecond)
        );
    }
}
