/*
 * JBMC environment model. Replaces: org.slf4j.LoggerFactory (slf4j-api 1.7.36).
 *
 * Why: the real LoggerFactory static initialiser performs logging-backend discovery
 * (ClassLoader.getSystemResources, logback static init), which JBMC cannot execute: the
 * missing JDK bodies become nondet stubs and produce spurious null-pointer counterexamples
 * before any trie code runs.
 *
 * Why it cannot change trie behaviour: co.rsk.trie only obtains a logger here and calls
 * Logger.error(String) on a "broken database" path; the result of a log call is never read.
 * The returned logger is slf4j's own real NOPLogger (from slf4j-api on the classpath),
 * whose methods have empty bodies.
 */
package org.slf4j;

import org.slf4j.helpers.NOPLogger;

public final class LoggerFactory {
    private LoggerFactory() { }

    public static Logger getLogger(Class<?> clazz) {
        return NOPLogger.NOP_LOGGER;
    }

    public static Logger getLogger(String name) {
        return NOPLogger.NOP_LOGGER;
    }
}
