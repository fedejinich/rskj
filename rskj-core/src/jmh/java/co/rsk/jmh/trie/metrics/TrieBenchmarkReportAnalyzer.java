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

package co.rsk.jmh.trie.metrics;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.infra.BenchmarkParams;
import org.openjdk.jmh.results.Result;
import org.openjdk.jmh.results.RunResult;
import org.openjdk.jmh.util.Statistics;

import java.io.IOException;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.TreeMap;

public final class TrieBenchmarkReportAnalyzer {

    public static final double AVG_REGRESSION_WARNING_THRESHOLD_PCT = 5.0;
    public static final double P95_REGRESSION_WARNING_THRESHOLD_PCT = 10.0;
    public static final double ALLOC_REGRESSION_WARNING_THRESHOLD_PCT = 15.0;
    public static final double VALUE_WRITE_REGRESSION_WARNING_THRESHOLD_PCT = 15.0;
    public static final double THROUGHPUT_DROP_WARNING_THRESHOLD_PCT = 5.0;

    private static final ObjectMapper JSON_MAPPER = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);

    public AnalysisReport analyze(Collection<RunResult> runResults, RunMetadata metadata) {
        Objects.requireNonNull(runResults, "runResults");
        Objects.requireNonNull(metadata, "metadata");

        Map<String, Map<String, EngineMetrics>> grouped = new TreeMap<>();

        for (RunResult runResult : runResults) {
            BenchmarkParams params = runResult.getParams();
            String workload = simpleBenchmarkName(params.getBenchmark());
            String engine = resolveEngineLabel(params);

            EngineMetrics metrics = grouped
                    .computeIfAbsent(workload, ignored -> new TreeMap<>())
                    .computeIfAbsent(engine, ignored -> new EngineMetrics(workload, engine));

            collectPrimaryMode(metrics, params.getMode(), runResult.getPrimaryResult());
            collectSecondary(metrics, params.getMode(), runResult.getSecondaryResults());
        }

        List<Map<String, Object>> workloadResults = new ArrayList<>();
        List<Map<String, Object>> comparison = new ArrayList<>();
        List<String> warnings = new ArrayList<>();

        for (Map.Entry<String, Map<String, EngineMetrics>> workloadEntry : grouped.entrySet()) {
            String workload = workloadEntry.getKey();
            Map<String, EngineMetrics> byEngine = workloadEntry.getValue();

            for (EngineMetrics metrics : byEngine.values()) {
                workloadResults.add(metrics.toSummaryMap());
            }

            List<Map<String, Object>> workloadComparisonRows = compareWorkload(workload, byEngine);
            comparison.addAll(workloadComparisonRows);
            for (Map<String, Object> row : workloadComparisonRows) {
                @SuppressWarnings("unchecked")
                List<String> rowWarnings = (List<String>) row.get("warnings");
                warnings.addAll(rowWarnings);
            }
        }

        Map<String, Object> summary = buildSummary(metadata, workloadResults, comparison, warnings);
        String comparisonMarkdown = buildComparisonMarkdown(metadata, comparison);
        return new AnalysisReport(summary, comparisonMarkdown, warnings);
    }

    private static void collectPrimaryMode(EngineMetrics metrics, Mode mode, Result<?> primaryResult) {
        String modeName = mode.name();
        ModeMetrics modeMetrics = metrics.modes.computeIfAbsent(modeName, ignored -> new ModeMetrics());

        modeMetrics.score = primaryResult.getScore();
        modeMetrics.scoreUnit = primaryResult.getScoreUnit();
        modeMetrics.sampleCount = primaryResult.getSampleCount();

        if (mode == Mode.AverageTime) {
            metrics.avgMicros = toMicros(primaryResult.getScore(), primaryResult.getScoreUnit());
        }

        if (mode == Mode.Throughput) {
            metrics.throughputOpsPerSec = toOpsPerSecond(primaryResult.getScore(), primaryResult.getScoreUnit());
        }

        if (mode == Mode.SampleTime) {
            Statistics statistics = primaryResult.getStatistics();
            if (statistics != null) {
                metrics.p50Micros = toMicros(statistics.getPercentile(50), primaryResult.getScoreUnit());
                metrics.p95Micros = toMicros(statistics.getPercentile(95), primaryResult.getScoreUnit());
                metrics.p99Micros = toMicros(statistics.getPercentile(99), primaryResult.getScoreUnit());

                modeMetrics.p50 = statistics.getPercentile(50);
                modeMetrics.p95 = statistics.getPercentile(95);
                modeMetrics.p99 = statistics.getPercentile(99);
                modeMetrics.percentileUnit = primaryResult.getScoreUnit();
            }
        }
    }

    private static void collectSecondary(EngineMetrics metrics, Mode mode, Map<String, Result> secondaryResults) {
        ModeMetrics modeMetrics = metrics.modes.computeIfAbsent(mode.name(), ignored -> new ModeMetrics());

        for (Map.Entry<String, Result> secondaryEntry : secondaryResults.entrySet()) {
            String key = secondaryEntry.getKey();
            Result<?> value = secondaryEntry.getValue();
            modeMetrics.secondary.put(key, value.getScore());
            modeMetrics.secondaryUnits.put(key, value.getScoreUnit());
        }

        metrics.gcAllocRateNormBytesPerOp = metrics.gcAllocRateNormBytesPerOp != null
                ? metrics.gcAllocRateNormBytesPerOp
                : findSecondaryMetricBySuffix(metrics, "gc.alloc.rate.norm");

        metrics.storeGetOpsPerOp = metrics.storeGetOpsPerOp != null
                ? metrics.storeGetOpsPerOp
                : findSecondaryMetricBySuffix(metrics, "store_get_ops");

        metrics.storePutOpsPerOp = metrics.storePutOpsPerOp != null
                ? metrics.storePutOpsPerOp
                : findSecondaryMetricBySuffix(metrics, "store_put_ops");

        metrics.storeDeleteOpsPerOp = metrics.storeDeleteOpsPerOp != null
                ? metrics.storeDeleteOpsPerOp
                : findSecondaryMetricBySuffix(metrics, "store_delete_ops");

        metrics.storeBytesReadPerOp = metrics.storeBytesReadPerOp != null
                ? metrics.storeBytesReadPerOp
                : findSecondaryMetricBySuffix(metrics, "store_bytes_read");

        metrics.storeBytesWrittenKeyPerOp = metrics.storeBytesWrittenKeyPerOp != null
                ? metrics.storeBytesWrittenKeyPerOp
                : findSecondaryMetricBySuffix(metrics, "store_bytes_written_key");

        metrics.storeBytesWrittenValuePerOp = metrics.storeBytesWrittenValuePerOp != null
                ? metrics.storeBytesWrittenValuePerOp
                : findSecondaryMetricBySuffix(metrics, "store_bytes_written_value");
    }

    private static Double findSecondaryMetricBySuffix(EngineMetrics metrics, String suffix) {
        if (metrics.modes.containsKey(Mode.AverageTime.name())) {
            Double fromAverageTime = metrics.modes.get(Mode.AverageTime.name()).findSecondaryBySuffix(suffix, false);
            if (fromAverageTime != null) {
                return fromAverageTime;
            }
        }

        if (metrics.modes.containsKey(Mode.SampleTime.name())) {
            Double fromSampleTime = metrics.modes.get(Mode.SampleTime.name()).findSecondaryBySuffix(suffix, true);
            if (fromSampleTime != null) {
                return fromSampleTime;
            }
        }

        if (metrics.modes.containsKey(Mode.Throughput.name())) {
            return metrics.modes.get(Mode.Throughput.name()).findSecondaryBySuffix(suffix, false);
        }

        return null;
    }

    private static List<Map<String, Object>> compareWorkload(String workload, Map<String, EngineMetrics> byEngine) {
        List<Map<String, Object>> rows = new ArrayList<>();
        EngineMetrics java = byEngine.get("java");
        if (java == null) {
            return rows;
        }

        List<String> candidates = byEngine.keySet().stream()
                .filter(engine -> engine.startsWith("rust"))
                .sorted()
                .toList();

        for (String candidateLabel : candidates) {
            EngineMetrics rust = byEngine.get(candidateLabel);
            if (rust == null) {
                continue;
            }

            Map<String, Object> comparison = new LinkedHashMap<>();
            comparison.put("benchmark", workload);
            comparison.put("candidate", candidateLabel);

            List<String> warnings = new ArrayList<>();

            Double avgDeltaPct = percentWorseLowerIsBetter(java.avgMicros, rust.avgMicros);
            Double p95DeltaPct = percentWorseLowerIsBetter(java.p95Micros, rust.p95Micros);
            Double allocDeltaPct = percentWorseLowerIsBetter(
                    java.gcAllocRateNormBytesPerOp,
                    rust.gcAllocRateNormBytesPerOp
            );
            Double bytesValueDeltaPct = percentWorseLowerIsBetter(
                    java.storeBytesWrittenValuePerOp,
                    rust.storeBytesWrittenValuePerOp
            );
            Double bytesReadDeltaPct = percentWorseLowerIsBetter(
                    java.storeBytesReadPerOp,
                    rust.storeBytesReadPerOp
            );
            Double throughputDropPct = percentDropHigherIsBetter(
                    java.throughputOpsPerSec,
                    rust.throughputOpsPerSec
            );

            if (avgDeltaPct != null && avgDeltaPct > AVG_REGRESSION_WARNING_THRESHOLD_PCT) {
                warnings.add(String.format(Locale.ROOT, "avg worsened %.2f%% (threshold %.2f%%)", avgDeltaPct, AVG_REGRESSION_WARNING_THRESHOLD_PCT));
            }

            if (p95DeltaPct != null && p95DeltaPct > P95_REGRESSION_WARNING_THRESHOLD_PCT) {
                warnings.add(String.format(Locale.ROOT, "p95 worsened %.2f%% (threshold %.2f%%)", p95DeltaPct, P95_REGRESSION_WARNING_THRESHOLD_PCT));
            }

            if (allocDeltaPct != null && allocDeltaPct > ALLOC_REGRESSION_WARNING_THRESHOLD_PCT) {
                warnings.add(String.format(Locale.ROOT, "alloc/op worsened %.2f%% (threshold %.2f%%)", allocDeltaPct, ALLOC_REGRESSION_WARNING_THRESHOLD_PCT));
            }

            if (bytesValueDeltaPct != null && bytesValueDeltaPct > VALUE_WRITE_REGRESSION_WARNING_THRESHOLD_PCT) {
                warnings.add(String.format(Locale.ROOT, "value-bytes-write/op worsened %.2f%% (threshold %.2f%%)", bytesValueDeltaPct, VALUE_WRITE_REGRESSION_WARNING_THRESHOLD_PCT));
            }

            if (throughputDropPct != null && throughputDropPct > THROUGHPUT_DROP_WARNING_THRESHOLD_PCT) {
                warnings.add(String.format(Locale.ROOT, "throughput dropped %.2f%% (threshold %.2f%%)", throughputDropPct, THROUGHPUT_DROP_WARNING_THRESHOLD_PCT));
            }

            comparison.put("status", warnings.isEmpty() ? "OK" : "WARNING");
            comparison.put("avgDeltaPct", avgDeltaPct);
            comparison.put("p95DeltaPct", p95DeltaPct);
            comparison.put("throughputDropPct", throughputDropPct);
            comparison.put("allocDeltaPct", allocDeltaPct);
            comparison.put("bytesWrittenValueDeltaPct", bytesValueDeltaPct);
            comparison.put("bytesReadDeltaPct", bytesReadDeltaPct);
            comparison.put("warnings", warnings);
            rows.add(comparison);
        }

        return rows;
    }

    private static Double percentWorseLowerIsBetter(Double baselineJava, Double candidateRust) {
        if (baselineJava == null || candidateRust == null || baselineJava == 0.0d) {
            return null;
        }

        return ((candidateRust - baselineJava) / baselineJava) * 100.0d;
    }

    private static Double percentDropHigherIsBetter(Double baselineJava, Double candidateRust) {
        if (baselineJava == null || candidateRust == null || baselineJava == 0.0d) {
            return null;
        }

        return ((baselineJava - candidateRust) / baselineJava) * 100.0d;
    }

    private static double toMicros(double score, String scoreUnit) {
        if (scoreUnit == null) {
            return score;
        }

        if (scoreUnit.startsWith("ns/")) {
            return score / 1_000.0d;
        }

        if (scoreUnit.startsWith("us/") || scoreUnit.startsWith("µs/")) {
            return score;
        }

        if (scoreUnit.startsWith("ms/")) {
            return score * 1_000.0d;
        }

        if (scoreUnit.startsWith("s/")) {
            return score * 1_000_000.0d;
        }

        return score;
    }

    private static double toOpsPerSecond(double score, String scoreUnit) {
        if (scoreUnit == null) {
            return score;
        }

        if ("ops/s".equals(scoreUnit)) {
            return score;
        }

        if ("ops/ms".equals(scoreUnit)) {
            return score * 1_000.0d;
        }

        if ("ops/us".equals(scoreUnit) || "ops/µs".equals(scoreUnit)) {
            return score * 1_000_000.0d;
        }

        if ("ops/ns".equals(scoreUnit)) {
            return score * 1_000_000_000.0d;
        }

        if ("ops/min".equals(scoreUnit)) {
            return score / 60.0d;
        }

        if ("ops/hr".equals(scoreUnit)) {
            return score / 3_600.0d;
        }

        return score;
    }

    private static String simpleBenchmarkName(String benchmark) {
        int separator = benchmark.lastIndexOf('.');
        return separator < 0 ? benchmark : benchmark.substring(separator + 1);
    }

    private static String resolveEngineLabel(BenchmarkParams params) {
        String engine = Optional.ofNullable(params.getParam("engine")).orElse("unknown");
        if (!"rust".equals(engine)) {
            return engine;
        }

        String rustImplementation = Optional.ofNullable(params.getParam("rustImplementation"))
                .orElse("legacy-v1")
                .trim()
                .toLowerCase(Locale.ROOT);
        return "rust(" + rustImplementation + ")";
    }

    private static Map<String, Object> buildSummary(
            RunMetadata metadata,
            List<Map<String, Object>> workloadResults,
            List<Map<String, Object>> comparison,
            List<String> warnings) {
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("generatedAt", metadata.generatedAt);
        summary.put("gitCommit", metadata.gitCommit);
        summary.put("jvm", metadata.jvm);
        summary.put("host", metadata.host);

        Map<String, Object> thresholds = new LinkedHashMap<>();
        thresholds.put("avgRegressionWarningPct", AVG_REGRESSION_WARNING_THRESHOLD_PCT);
        thresholds.put("p95RegressionWarningPct", P95_REGRESSION_WARNING_THRESHOLD_PCT);
        thresholds.put("allocRegressionWarningPct", ALLOC_REGRESSION_WARNING_THRESHOLD_PCT);
        thresholds.put("valueWriteRegressionWarningPct", VALUE_WRITE_REGRESSION_WARNING_THRESHOLD_PCT);
        thresholds.put("throughputDropWarningPct", THROUGHPUT_DROP_WARNING_THRESHOLD_PCT);
        summary.put("thresholds", thresholds);

        summary.put("results", workloadResults);
        summary.put("comparison", comparison);
        summary.put("warnings", warnings);

        return summary;
    }

    private static String buildComparisonMarkdown(RunMetadata metadata, List<Map<String, Object>> comparisonRows) {
        StringBuilder output = new StringBuilder();
        output.append("# Trie Engine Benchmark Comparison (Java vs Rust)\n\n");
        output.append("Generated at: ").append(metadata.generatedAt).append('\n');
        output.append("Git commit: ").append(metadata.gitCommit).append('\n');
        output.append("JVM: ").append(metadata.jvm).append('\n');
        output.append("Host: ").append(metadata.host).append("\n\n");

        output.append("| Workload | Candidate | Status | Avg Δ% | P95 Δ% | Throughput drop % | Alloc Δ% | Value bytes write Δ% | Read bytes Δ% | Warnings |\n");
        output.append("|---|---|---|---:|---:|---:|---:|---:|---:|---|\n");

        for (Map<String, Object> row : comparisonRows) {
            @SuppressWarnings("unchecked")
            List<String> warnings = (List<String>) row.get("warnings");
            output
                    .append("| ").append(row.get("benchmark"))
                    .append(" | ").append(row.getOrDefault("candidate", "rust"))
                    .append(" | ").append(row.get("status"))
                    .append(" | ").append(formatPercent(row.get("avgDeltaPct")))
                    .append(" | ").append(formatPercent(row.get("p95DeltaPct")))
                    .append(" | ").append(formatPercent(row.get("throughputDropPct")))
                    .append(" | ").append(formatPercent(row.get("allocDeltaPct")))
                    .append(" | ").append(formatPercent(row.get("bytesWrittenValueDeltaPct")))
                    .append(" | ").append(formatPercent(row.get("bytesReadDeltaPct")))
                    .append(" | ").append(warnings.isEmpty() ? "-" : String.join("; ", warnings))
                    .append(" |\n");
        }

        return output.toString();
    }

    private static String formatPercent(Object value) {
        if (!(value instanceof Double)) {
            return "n/a";
        }

        return String.format(Locale.ROOT, "%.2f%%", (Double) value);
    }

    public static final class AnalysisReport {
        private final Map<String, Object> summary;
        private final String comparisonMarkdown;
        private final List<String> warnings;

        private AnalysisReport(Map<String, Object> summary, String comparisonMarkdown, List<String> warnings) {
            this.summary = summary;
            this.comparisonMarkdown = comparisonMarkdown;
            this.warnings = warnings;
        }

        public List<String> getWarnings() {
            return Collections.unmodifiableList(warnings);
        }

        public void write(Path summaryPath, Path comparisonPath) throws IOException {
            Files.createDirectories(summaryPath.getParent());
            Files.createDirectories(comparisonPath.getParent());
            JSON_MAPPER.writeValue(summaryPath.toFile(), summary);
            Files.writeString(comparisonPath, comparisonMarkdown);
        }
    }

    public static final class RunMetadata {
        private final String generatedAt;
        private final String gitCommit;
        private final String jvm;
        private final String host;

        public RunMetadata(String generatedAt, String gitCommit, String jvm, String host) {
            this.generatedAt = generatedAt;
            this.gitCommit = gitCommit;
            this.jvm = jvm;
            this.host = host;
        }

        public static RunMetadata capture(String gitCommit) {
            String generatedAt = Instant.now().toString();
            String jvm = System.getProperty("java.version") + " (" + System.getProperty("java.vendor") + ")";
            return new RunMetadata(generatedAt, gitCommit, jvm, resolveHostName());
        }

        private static String resolveHostName() {
            try {
                return InetAddress.getLocalHost().getHostName();
            } catch (UnknownHostException e) {
                return "unknown";
            }
        }
    }

    private static final class EngineMetrics {
        private final String benchmark;
        private final String engine;
        private final Map<String, ModeMetrics> modes = new LinkedHashMap<>();

        private Double avgMicros;
        private Double p50Micros;
        private Double p95Micros;
        private Double p99Micros;
        private Double throughputOpsPerSec;
        private Double gcAllocRateNormBytesPerOp;
        private Double storeGetOpsPerOp;
        private Double storePutOpsPerOp;
        private Double storeDeleteOpsPerOp;
        private Double storeBytesReadPerOp;
        private Double storeBytesWrittenKeyPerOp;
        private Double storeBytesWrittenValuePerOp;

        private EngineMetrics(String benchmark, String engine) {
            this.benchmark = benchmark;
            this.engine = engine;
        }

        private Map<String, Object> toSummaryMap() {
            Map<String, Object> output = new LinkedHashMap<>();
            output.put("benchmark", benchmark);
            output.put("engine", engine);

            Map<String, Object> modeResults = new LinkedHashMap<>();
            for (Map.Entry<String, ModeMetrics> modeEntry : modes.entrySet()) {
                modeResults.put(modeEntry.getKey(), modeEntry.getValue().toMap());
            }
            output.put("modes", modeResults);

            Map<String, Object> metrics = new LinkedHashMap<>();
            metrics.put("avgMicros", avgMicros);
            metrics.put("p50Micros", p50Micros);
            metrics.put("p95Micros", p95Micros);
            metrics.put("p99Micros", p99Micros);
            metrics.put("throughputOpsPerSec", throughputOpsPerSec);
            metrics.put("gcAllocRateNormBytesPerOp", gcAllocRateNormBytesPerOp);
            metrics.put("storeGetOpsPerOp", storeGetOpsPerOp);
            metrics.put("storePutOpsPerOp", storePutOpsPerOp);
            metrics.put("storeDeleteOpsPerOp", storeDeleteOpsPerOp);
            metrics.put("storeBytesReadPerOp", storeBytesReadPerOp);
            metrics.put("storeBytesWrittenKeyPerOp", storeBytesWrittenKeyPerOp);
            metrics.put("storeBytesWrittenValuePerOp", storeBytesWrittenValuePerOp);
            output.put("metrics", metrics);
            return output;
        }
    }

    private static final class ModeMetrics {
        private Double score;
        private String scoreUnit;
        private long sampleCount;
        private Double p50;
        private Double p95;
        private Double p99;
        private String percentileUnit;
        private final Map<String, Double> secondary = new LinkedHashMap<>();
        private final Map<String, String> secondaryUnits = new LinkedHashMap<>();

        private Double findSecondaryBySuffix(String suffix, boolean normalizeCountMetrics) {
            for (Map.Entry<String, Double> entry : secondary.entrySet()) {
                String key = entry.getKey();
                if (key.equals(suffix)
                        || key.endsWith('.' + suffix)
                        || key.endsWith(':' + suffix)
                        || key.contains(suffix)) {
                    Double value = entry.getValue();
                    String unit = secondaryUnits.get(key);
                    if (normalizeCountMetrics && "#".equals(unit) && sampleCount > 0) {
                        return value / sampleCount;
                    }

                    return value;
                }
            }

            return null;
        }

        private Map<String, Object> toMap() {
            Map<String, Object> output = new LinkedHashMap<>();
            output.put("score", score);
            output.put("scoreUnit", scoreUnit);
            output.put("sampleCount", sampleCount);
            output.put("p50", p50);
            output.put("p95", p95);
            output.put("p99", p99);
            output.put("percentileUnit", percentileUnit);

            Map<String, Object> secondaryOutput = new LinkedHashMap<>();
            for (Map.Entry<String, Double> secondaryEntry : secondary.entrySet()) {
                Map<String, Object> metric = new LinkedHashMap<>();
                metric.put("score", secondaryEntry.getValue());
                metric.put("unit", secondaryUnits.get(secondaryEntry.getKey()));
                secondaryOutput.put(secondaryEntry.getKey(), metric);
            }
            output.put("secondary", secondaryOutput);
            return output;
        }
    }
}
