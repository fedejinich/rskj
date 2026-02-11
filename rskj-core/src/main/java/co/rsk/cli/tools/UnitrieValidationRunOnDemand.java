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
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.ethereum.core.Block;
import org.ethereum.core.Transaction;
import org.ethereum.db.BlockStore;
import org.ethereum.util.ByteUtil;
import picocli.CommandLine;

import javax.annotation.Nullable;
import java.io.IOException;
import java.lang.invoke.MethodHandles;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@CommandLine.Command(
        name = "unitrie-validation-run",
        mixinStandardHelpOptions = true,
        version = "unitrie-validation-run 1.0",
        description = "Validation Run (On-Demand) for Java vs Rust Unitrie parity"
)
public class UnitrieValidationRunOnDemand extends PicoCliToolRskContextAware {

    private static final DateTimeFormatter RUN_TIMESTAMP_FORMATTER =
            DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").withZone(ZoneOffset.UTC);
    private static final ObjectMapper JSON_MAPPER = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);

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
            names = {"--repeatRuns"},
            description = "How many consecutive runs to execute for the same range (-1 uses profile default)",
            defaultValue = "-1"
    )
    private int repeatRuns;

    @CommandLine.Option(
            names = {"--artifactLevel"},
            description = "Artifact detail level: basic|extended",
            defaultValue = "extended"
    )
    private String artifactLevel;

    @CommandLine.Option(
            names = {"--captureCorpusOnMismatch"},
            description = "Capture automatic differential corpus after first mismatch",
            defaultValue = "true"
    )
    private boolean captureCorpusOnMismatch;

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
            names = {"--runId"},
            description = "Optional run identifier used for reproducible artifacts"
    )
    @Nullable
    private String runId;

    @CommandLine.Option(
            names = {"--reportDir"},
            description = "Directory where validation artifacts are written",
            defaultValue = "build/reports/unitrie-validation"
    )
    private Path reportDir;

    @CommandLine.Option(
            names = {"--corpusOutDir"},
            description = "Directory where auto-generated differential corpus is written",
            defaultValue = "build/reports/unitrie-validation/corpus"
    )
    private Path corpusOutDir;

    public static void main(String[] args) {
        create(MethodHandles.lookup().lookupClass()).execute(args);
    }

    @Override
    public Integer call() throws IOException {
        ArtifactLevel effectiveArtifactLevel = ArtifactLevel.parse(artifactLevel);
        int effectiveBlockCount = resolveBlockCount();
        int effectiveRepeatRuns = resolveRepeatRuns();
        long toBlock = fromBlock + effectiveBlockCount - 1L;
        String effectiveRunId = resolveRunId();

        printInfo(
                "Starting Validation Run (On-Demand): runId={} fromBlock={} toBlock={} blockCount={} repeatRuns={} profile={}",
                effectiveRunId,
                fromBlock,
                toBlock,
                effectiveBlockCount,
                effectiveRepeatRuns,
                deepProfile ? "deep" : "fast"
        );

        for (int attemptIndex = 1; attemptIndex <= effectiveRepeatRuns; attemptIndex++) {
            Path attemptDir = reportDir.resolve("run-" + effectiveRunId + "-attempt-" + attemptIndex);
            Files.createDirectories(attemptDir);
            writeRunManifest(
                    attemptDir,
                    effectiveRunId,
                    attemptIndex,
                    effectiveBlockCount,
                    effectiveRepeatRuns,
                    toBlock,
                    effectiveArtifactLevel
            );

            ValidationRunSummary summary = runAttempt(
                    effectiveRunId,
                    attemptIndex,
                    effectiveBlockCount,
                    toBlock,
                    attemptDir,
                    effectiveArtifactLevel
            );

            printMetrics("java", summary.getJavaNanos(), summary.getProcessedBlocks());
            printMetrics("rust", summary.getRustNanos(), summary.getProcessedBlocks());
            printInfo(
                    "runId={} attempt={} processedBlocks={} divergences={} rustExceptions={}",
                    effectiveRunId,
                    attemptIndex,
                    summary.getProcessedBlocks(),
                    summary.getDivergenceCount(),
                    summary.getRustExceptionsCount()
            );

            if (!summary.isSuccessful()) {
                printError(
                        "Validation run failed at attempt {} for runId {}. No further attempts will be executed.",
                        attemptIndex,
                        effectiveRunId
                );
                return 1;
            }
        }

        printInfo(
                "Validation Run (On-Demand) completed successfully for runId={} with {} consecutive clean attempts",
                effectiveRunId,
                effectiveRepeatRuns
        );
        return 0;
    }

    private int resolveBlockCount() {
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
            throw new IllegalArgumentException("blockCount must be greater than zero");
        }

        return effectiveBlockCount;
    }

    private int resolveRepeatRuns() {
        if (repeatRuns > 0) {
            return repeatRuns;
        }

        return deepProfile ? 2 : 1;
    }

    private String resolveRunId() {
        if (runId == null || runId.trim().isEmpty()) {
            return RUN_TIMESTAMP_FORMATTER.format(Instant.now());
        }

        return runId.trim();
    }

    private ValidationRunSummary runAttempt(
            String effectiveRunId,
            int attemptIndex,
            int effectiveBlockCount,
            long toBlock,
            Path attemptDir,
            ArtifactLevel effectiveArtifactLevel) throws IOException {
        BlockStore blockStore = ctx.getBlockStore();
        BlockExecutor javaExecutor = buildExecutor(TrieEngineType.JAVA, true, null);
        BlockExecutor rustExecutor = buildExecutor(TrieEngineType.RUST, true, rustLibraryPath);

        long javaNanos = 0L;
        long rustNanos = 0L;
        int processedBlocks = 0;
        int divergenceCount = 0;
        int rustExceptionCount = 0;

        for (long blockNumber = fromBlock; blockNumber <= toBlock; blockNumber++) {
            Block block = blockStore.getChainBlockByNumber(blockNumber);
            if (block == null) {
                printError("Block {} not found in chain", blockNumber);
                break;
            }

            Block parent = blockStore.getBlockByHash(block.getParentHash().getBytes());
            if (parent == null) {
                printError("Parent block not found for block {}", blockNumber);
                break;
            }

            long javaStart = System.nanoTime();
            BlockResult javaResult = javaExecutor.execute(null, 0, block, parent.getHeader(), false, false, false);
            long javaBlockNanos = System.nanoTime() - javaStart;
            javaNanos += javaBlockNanos;

            long rustStart = System.nanoTime();
            BlockResult rustResult;
            try {
                rustResult = rustExecutor.execute(null, 0, block, parent.getHeader(), false, false, false);
            } catch (RuntimeException ex) {
                long rustBlockNanos = System.nanoTime() - rustStart;
                rustNanos += rustBlockNanos;
                rustExceptionCount++;

                UnitrieDivergenceArtifact artifact = buildDivergenceArtifact(
                        "Rust execution failed with exception: " + ex.getMessage(),
                        effectiveRunId,
                        attemptIndex,
                        block,
                        null,
                        null,
                        nanosToMillis(javaBlockNanos),
                        nanosToMillis(rustBlockNanos),
                        effectiveArtifactLevel,
                        ex
                );
                Path textPath = writeDivergenceArtifact(attemptDir, artifact);
                printError("Rust execution failed at block {}. Artifact: {}", blockNumber, textPath);
                break;
            }

            long rustBlockNanos = System.nanoTime() - rustStart;
            rustNanos += rustBlockNanos;
            processedBlocks++;

            byte[] javaRoot = javaResult.getFinalState().getHash().getBytes();
            byte[] rustRoot = rustResult.getFinalState().getHash().getBytes();

            if (!Arrays.equals(javaRoot, rustRoot)) {
                divergenceCount++;

                UnitrieDivergenceArtifact artifact = buildDivergenceArtifact(
                        "State root divergence detected between Java and Rust engines",
                        effectiveRunId,
                        attemptIndex,
                        block,
                        javaRoot,
                        rustRoot,
                        nanosToMillis(javaBlockNanos),
                        nanosToMillis(rustBlockNanos),
                        effectiveArtifactLevel,
                        null
                );
                Path textPath = writeDivergenceArtifact(attemptDir, artifact);
                printError(
                        "Mismatch at block {} javaRoot={} rustRoot={} artifact={}",
                        blockNumber,
                        ByteUtil.toHexString(javaRoot),
                        ByteUtil.toHexString(rustRoot),
                        textPath
                );

                if (captureCorpusOnMismatch) {
                    printInfo("Auto corpus capture requested for mismatch block {} (pending diagnostic implementation)", blockNumber);
                }

                if (failFast) {
                    break;
                }
            }
        }

        return new ValidationRunSummary(
                attemptIndex,
                fromBlock,
                toBlock,
                effectiveBlockCount,
                processedBlocks,
                divergenceCount,
                rustExceptionCount,
                javaNanos,
                rustNanos
        );
    }

    private void writeRunManifest(
            Path attemptDir,
            String effectiveRunId,
            int attemptIndex,
            int effectiveBlockCount,
            int effectiveRepeatRuns,
            long toBlock,
            ArtifactLevel artifactLevelValue) throws IOException {
        Map<String, Object> manifest = new LinkedHashMap<>();
        manifest.put("runId", effectiveRunId);
        manifest.put("attemptIndex", attemptIndex);
        manifest.put("attemptsTotal", effectiveRepeatRuns);
        manifest.put("timestampUtc", Instant.now().toString());
        manifest.put("fromBlock", fromBlock);
        manifest.put("toBlock", toBlock);
        manifest.put("blockCount", effectiveBlockCount);
        manifest.put("deepProfile", deepProfile);
        manifest.put("failFast", failFast);
        manifest.put("artifactLevel", artifactLevelValue.name().toLowerCase());
        manifest.put("captureCorpusOnMismatch", captureCorpusOnMismatch);
        manifest.put("reportDir", reportDir.toAbsolutePath().toString());
        manifest.put("corpusOutDir", corpusOutDir.toAbsolutePath().toString());
        manifest.put("rustLibraryPath", rustLibraryPath);
        manifest.put("engineConfig", "java-vs-rust");
        manifest.put("rustFailOnMismatch", true);
        manifest.put("host", resolveHostName());
        manifest.put("gitCommit", ctx.getBuildInfo().getBuildHash());

        Path manifestPath = attemptDir.resolve("run-manifest.json");
        JSON_MAPPER.writeValue(manifestPath.toFile(), manifest);
    }

    private Path writeDivergenceArtifact(Path runDir, UnitrieDivergenceArtifact artifact) throws IOException {
        long blockNumber = artifact.getBlock().getNumber();
        Path textPath = runDir.resolve("mismatch-block-" + blockNumber + ".txt");
        Path jsonPath = runDir.resolve("mismatch-block-" + blockNumber + ".json");

        Files.writeString(textPath, toHumanReadableArtifact(artifact), StandardCharsets.UTF_8);
        JSON_MAPPER.writeValue(jsonPath.toFile(), artifact);
        return textPath;
    }

    private String toHumanReadableArtifact(UnitrieDivergenceArtifact artifact) {
        StringBuilder content = new StringBuilder();
        content.append("reason=").append(artifact.getReason()).append('\n');
        content.append("runId=").append(artifact.getRunId()).append('\n');
        content.append("attemptIndex=").append(artifact.getAttemptIndex()).append('\n');
        content.append("block.number=").append(artifact.getBlock().getNumber()).append('\n');
        content.append("block.hash=").append(artifact.getBlock().getHash()).append('\n');
        content.append("block.parentHash=").append(artifact.getBlock().getParentHash()).append('\n');
        content.append("block.stateRoot=").append(artifact.getBlock().getStateRoot()).append('\n');
        content.append("java.root=").append(nullableString(artifact.getRoots().getJavaRoot())).append('\n');
        content.append("rust.root=").append(nullableString(artifact.getRoots().getRustRoot())).append('\n');

        if (artifact.getTiming() != null) {
            content.append("java.ms.block=").append(String.format("%.3f", artifact.getTiming().getJavaMsBlock())).append('\n');
            content.append("rust.ms.block=").append(String.format("%.3f", artifact.getTiming().getRustMsBlock())).append('\n');
            content.append("delta.ms=").append(String.format("%.3f", artifact.getTiming().getDeltaMs())).append('\n');
        }

        content.append("tx.count=").append(artifact.getTx().getCount()).append('\n');
        content.append("tx.hashes=").append(String.join(",", artifact.getTx().getHashes())).append('\n');
        content.append("config.engine=").append(artifact.getConfig().getEngine()).append('\n');
        content.append("config.failFast=").append(artifact.getConfig().isFailFast()).append('\n');
        content.append("config.failOnMismatch=").append(artifact.getConfig().isFailOnMismatch()).append('\n');
        content.append("config.rustLibraryPath=").append(nullableString(artifact.getConfig().getRustLibraryPath())).append('\n');

        if (artifact.getException() != null) {
            content.append("exception.class=").append(artifact.getException().getClassName()).append('\n');
            content.append("exception.message=").append(artifact.getException().getMessage()).append('\n');
        }

        return content.toString();
    }

    private UnitrieDivergenceArtifact buildDivergenceArtifact(
            String reason,
            String effectiveRunId,
            int attemptIndex,
            Block block,
            @Nullable byte[] javaRoot,
            @Nullable byte[] rustRoot,
            double javaMsBlock,
            double rustMsBlock,
            ArtifactLevel effectiveArtifactLevel,
            @Nullable RuntimeException exception) {
        boolean includeExtended = effectiveArtifactLevel == ArtifactLevel.EXTENDED;
        List<String> txHashes = includeExtended
                ? block.getTransactionsList().stream()
                .map(Transaction::getHash)
                .map(hash -> hash.toHexString())
                .collect(Collectors.toList())
                : List.of();

        UnitrieDivergenceArtifact.BlockInfo blockInfo = new UnitrieDivergenceArtifact.BlockInfo(
                block.getNumber(),
                block.getHash().toHexString(),
                block.getParentHash().toHexString(),
                ByteUtil.toHexString(block.getStateRoot())
        );
        UnitrieDivergenceArtifact.RootInfo roots = new UnitrieDivergenceArtifact.RootInfo(
                nullableHex(javaRoot),
                nullableHex(rustRoot)
        );
        UnitrieDivergenceArtifact.TimingInfo timingInfo = new UnitrieDivergenceArtifact.TimingInfo(
                includeExtended ? javaMsBlock : 0.0d,
                includeExtended ? rustMsBlock : 0.0d,
                includeExtended ? rustMsBlock - javaMsBlock : 0.0d
        );
        UnitrieDivergenceArtifact.TxInfo txInfo = new UnitrieDivergenceArtifact.TxInfo(
                block.getTransactionsList().size(),
                txHashes
        );
        UnitrieDivergenceArtifact.ConfigInfo configInfo = new UnitrieDivergenceArtifact.ConfigInfo(
                "java-vs-rust",
                failFast,
                true,
                rustLibraryPath
        );
        UnitrieDivergenceArtifact.ExceptionInfo exceptionInfo = exception == null
                ? null
                : new UnitrieDivergenceArtifact.ExceptionInfo(
                exception.getClass().getName(),
                nullableString(exception.getMessage())
        );

        return new UnitrieDivergenceArtifact(
                reason,
                effectiveRunId,
                attemptIndex,
                blockInfo,
                roots,
                timingInfo,
                txInfo,
                configInfo,
                exceptionInfo
        );
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

    private static double nanosToMillis(long nanos) {
        return nanos / 1_000_000.0d;
    }

    private static String resolveHostName() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }

    @Nullable
    private static String nullableHex(@Nullable byte[] value) {
        return value == null ? null : ByteUtil.toHexString(value);
    }

    private static String nullableString(@Nullable String value) {
        return value == null ? "null" : value;
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

    private enum ArtifactLevel {
        BASIC,
        EXTENDED;

        private static ArtifactLevel parse(String value) {
            String normalized = value == null ? "" : value.trim().toLowerCase();
            if ("basic".equals(normalized)) {
                return BASIC;
            }

            if ("extended".equals(normalized)) {
                return EXTENDED;
            }

            throw new IllegalArgumentException("artifactLevel must be one of: basic, extended");
        }
    }
}
