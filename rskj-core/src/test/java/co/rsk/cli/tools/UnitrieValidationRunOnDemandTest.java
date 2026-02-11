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

import org.junit.jupiter.api.Test;
import picocli.CommandLine;

import java.lang.reflect.Field;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class UnitrieValidationRunOnDemandTest {

    @Test
    void parsesNewOptionsForSustainedGate() throws Exception {
        UnitrieValidationRunOnDemand tool = new UnitrieValidationRunOnDemand();
        new CommandLine(tool).parseArgs(
                "--fromBlock", "123",
                "--repeatRuns", "2",
                "--artifactLevel", "basic",
                "--captureCorpusOnMismatch=false",
                "--runId", "run-fixed",
                "--corpusOutDir", "build/test-corpus"
        );

        assertEquals(123L, getLongField(tool, "fromBlock"));
        assertEquals(2, getIntField(tool, "repeatRuns"));
        assertEquals("basic", getStringField(tool, "artifactLevel"));
        assertFalse(getBooleanField(tool, "captureCorpusOnMismatch"));
        assertEquals("run-fixed", getStringField(tool, "runId"));
        assertEquals(Path.of("build/test-corpus"), getPathField(tool, "corpusOutDir"));
    }

    @Test
    void keepsExpectedDefaultsForMvpFlow() throws Exception {
        UnitrieValidationRunOnDemand tool = new UnitrieValidationRunOnDemand();
        new CommandLine(tool).parseArgs("--fromBlock", "500");

        assertEquals(-1, getIntField(tool, "repeatRuns"));
        assertEquals("extended", getStringField(tool, "artifactLevel"));
        assertEquals(true, getBooleanField(tool, "captureCorpusOnMismatch"));
    }

    private static int getIntField(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return (int) field.get(target);
    }

    private static long getLongField(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return (long) field.get(target);
    }

    private static boolean getBooleanField(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return (boolean) field.get(target);
    }

    private static String getStringField(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return (String) field.get(target);
    }

    private static Path getPathField(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return (Path) field.get(target);
    }
}
