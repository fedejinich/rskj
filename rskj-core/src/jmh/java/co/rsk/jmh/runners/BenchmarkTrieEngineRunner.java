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

package co.rsk.jmh.runners;

import co.rsk.jmh.trie.metrics.TrieBenchmarkReportAnalyzer;
import co.rsk.jmh.trie.TrieEngineBenchmark;
import org.openjdk.jmh.results.format.ResultFormatType;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;
import org.openjdk.jmh.runner.options.TimeValue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Collection;

public class BenchmarkTrieEngineRunner {

    private static final String ENGINES_PROPERTY = "unitrie.jmh.engines";
    private static final String FAIL_ON_MISMATCH_PROPERTY = "unitrie.jmh.failOnMismatch";
    private static final String RUST_LIBRARY_PATH_PROPERTY = "unitrie.jmh.rustLibraryPath";
    private static final String RUST_IMPLEMENTATIONS_PROPERTY = "unitrie.jmh.rustImplementations";
    private static final String WARMUP_ITERATIONS_PROPERTY = "unitrie.jmh.warmupIterations";
    private static final String MEASUREMENT_ITERATIONS_PROPERTY = "unitrie.jmh.measurementIterations";
    private static final String WARMUP_SECONDS_PROPERTY = "unitrie.jmh.warmupSeconds";
    private static final String MEASUREMENT_SECONDS_PROPERTY = "unitrie.jmh.measurementSeconds";
    private static final String FORKS_PROPERTY = "unitrie.jmh.forks";
    private static final String ENGINES_ENV = "UNITRIE_JMH_ENGINES";
    private static final String FAIL_ON_MISMATCH_ENV = "UNITRIE_JMH_FAIL_ON_MISMATCH";
    private static final String RUST_LIBRARY_PATH_ENV = "UNITRIE_JMH_RUST_LIBRARY_PATH";
    private static final String RUST_IMPLEMENTATIONS_ENV = "UNITRIE_JMH_RUST_IMPLEMENTATIONS";
    private static final String WARMUP_ITERATIONS_ENV = "UNITRIE_JMH_WARMUP_ITERATIONS";
    private static final String MEASUREMENT_ITERATIONS_ENV = "UNITRIE_JMH_MEASUREMENT_ITERATIONS";
    private static final String WARMUP_SECONDS_ENV = "UNITRIE_JMH_WARMUP_SECONDS";
    private static final String MEASUREMENT_SECONDS_ENV = "UNITRIE_JMH_MEASUREMENT_SECONDS";
    private static final String FORKS_ENV = "UNITRIE_JMH_FORKS";

    public static void main(String[] args) throws RunnerException, IOException {
        Path reportsDir = Paths.get(System.getProperty("user.dir"), "build", "reports", "jmh");
        Path reportPath = reportsDir.resolve("result_trie_engine.csv");
        Path summaryPath = reportsDir.resolve("result_trie_engine_summary.json");
        Path comparisonPath = reportsDir.resolve("result_trie_engine_comparison.md");
        createReportDirectory(reportPath);

        String[] engines = resolveEngines();
        String failOnMismatch = resolveConfig(FAIL_ON_MISMATCH_PROPERTY, FAIL_ON_MISMATCH_ENV, "true");
        String rustLibraryPath = resolveConfig(RUST_LIBRARY_PATH_PROPERTY, RUST_LIBRARY_PATH_ENV, "");
        String[] rustImplementations = resolveRustImplementations();
        int warmupIterations = Integer.parseInt(resolveConfig(WARMUP_ITERATIONS_PROPERTY, WARMUP_ITERATIONS_ENV, "5"));
        int measurementIterations = Integer.parseInt(resolveConfig(MEASUREMENT_ITERATIONS_PROPERTY, MEASUREMENT_ITERATIONS_ENV, "15"));
        int warmupSeconds = Integer.parseInt(resolveConfig(WARMUP_SECONDS_PROPERTY, WARMUP_SECONDS_ENV, "10"));
        int measurementSeconds = Integer.parseInt(resolveConfig(MEASUREMENT_SECONDS_PROPERTY, MEASUREMENT_SECONDS_ENV, "10"));
        int forks = Integer.parseInt(resolveConfig(FORKS_PROPERTY, FORKS_ENV, "1"));

        Options options = new OptionsBuilder()
                .include(TrieEngineBenchmark.class.getName())
                .warmupIterations(warmupIterations)
                .warmupTime(TimeValue.seconds(warmupSeconds))
                .measurementIterations(measurementIterations)
                .measurementTime(TimeValue.seconds(measurementSeconds))
                .param("engine", engines)
                .param("failOnMismatch", failOnMismatch)
                .param("rustLibraryPath", rustLibraryPath)
                .param("rustImplementation", rustImplementations)
                .forks(forks)
                .addProfiler("gc")
                .result(reportPath.toString())
                .resultFormat(ResultFormatType.CSV)
                .shouldFailOnError(true)
                .build();

        Collection<org.openjdk.jmh.results.RunResult> runResults = new Runner(options).run();

        TrieBenchmarkReportAnalyzer analyzer = new TrieBenchmarkReportAnalyzer();
        TrieBenchmarkReportAnalyzer.AnalysisReport report = analyzer.analyze(
                runResults,
                TrieBenchmarkReportAnalyzer.RunMetadata.capture(resolveGitCommit())
        );
        report.write(summaryPath, comparisonPath);

        System.out.printf("JMH raw results: %s%n", reportPath);
        System.out.printf("JMH summary: %s%n", summaryPath);
        System.out.printf("JMH comparison: %s%n", comparisonPath);
        if (report.getWarnings().isEmpty()) {
            System.out.println("Trie benchmark comparison status: OK");
        } else {
            System.out.println("Trie benchmark comparison status: WARNING");
            for (String warning : report.getWarnings()) {
                System.out.printf("  - %s%n", warning);
            }
        }
    }

    private static void createReportDirectory(Path reportPath) {
        try {
            Files.createDirectories(reportPath.getParent());
        } catch (IOException e) {
            throw new IllegalStateException("Cannot create JMH report directory", e);
        }
    }

    private static String[] resolveEngines() {
        String configured = resolveConfig(ENGINES_PROPERTY, ENGINES_ENV, "java,rust");
        String[] values = Arrays.stream(configured.split(","))
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .toArray(String[]::new);

        return values.length == 0 ? new String[]{"java", "rust"} : values;
    }

    private static String[] resolveRustImplementations() {
        String configured = resolveConfig(RUST_IMPLEMENTATIONS_PROPERTY, RUST_IMPLEMENTATIONS_ENV, "legacy-v1,next");
        String[] values = Arrays.stream(configured.split(","))
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .toArray(String[]::new);

        return values.length == 0 ? new String[]{"legacy-v1", "next"} : values;
    }

    private static String resolveConfig(String propertyName, String envVarName, String defaultValue) {
        String fromProperty = System.getProperty(propertyName);
        if (fromProperty != null && !fromProperty.isBlank()) {
            return fromProperty;
        }

        String fromEnv = System.getenv(envVarName);
        if (fromEnv != null && !fromEnv.isBlank()) {
            return fromEnv;
        }

        return defaultValue;
    }

    private static String resolveGitCommit() {
        try {
            Process process = new ProcessBuilder("git", "rev-parse", "--short", "HEAD")
                    .redirectErrorStream(true)
                    .start();
            byte[] output = process.getInputStream().readAllBytes();
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                return "unknown";
            }

            String commit = new String(output).trim();
            return commit.isEmpty() ? "unknown" : commit;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return "unknown";
        } catch (IOException e) {
            return "unknown";
        }
    }
}
