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

import co.rsk.jmh.trie.TrieEngineBenchmark;
import org.openjdk.jmh.results.format.ResultFormatType;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class BenchmarkTrieEngineRunner {

    public static void main(String[] args) throws RunnerException {
        Path reportPath = Paths.get(System.getProperty("user.dir"), "build", "reports", "jmh", "result_trie_engine.csv");
        createReportDirectory(reportPath);

        Options options = new OptionsBuilder()
                .include(TrieEngineBenchmark.class.getName())
                .forks(1)
                .result(reportPath.toString())
                .resultFormat(ResultFormatType.CSV)
                .shouldFailOnError(true)
                .build();

        new Runner(options).run();
    }

    private static void createReportDirectory(Path reportPath) {
        try {
            Files.createDirectories(reportPath.getParent());
        } catch (IOException e) {
            throw new IllegalStateException("Cannot create JMH report directory", e);
        }
    }
}
