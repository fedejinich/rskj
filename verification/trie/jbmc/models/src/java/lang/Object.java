/*
 * JBMC environment model. Replaces: java.lang.Object from JBMC's java-models-library (commit
 * c7835345, src/main/java/java/lang/Object.java). This file is that model verbatim except getClass().
 *
 * Why: the library's getClass() returns Class.forName(CProver.classIdentifier(this)), which allocates
 * a NEW Class object (and a fresh string through JBMC's string solver) on every call. Hence
 * `a.getClass() == b.getClass()` is always false in JBMC, while on the JVM it is true for objects of
 * the same class. rskj uses exactly that idiom in Uint24.equals, Uint16/Uint8.equals,
 * Keccak256.equals and Trie.equals (e.g. Trie.java:847 compares value lengths with Uint24.equals),
 * so the library model changes trie behaviour.
 *
 * Model: getClass() returns one canonical Class object per class for the classes listed below
 * (JbmcCanonicalClasses); each is final or has no subclass in rskj-core, so instanceof determines
 * the exact runtime class and identity comparisons behave as on the JVM (one documented exception:
 * RskAddress, whose only subclass is the REMASC address constant, see getClass()). Any other receiver is an
 * assertion failure: no property can silently depend on a wrong class identity. To extend, add the
 * class here and in JbmcCanonicalClasses after checking it has no subclasses.
 */
/*
 * Copyright (c) 1994, 2012, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

package java.lang;

import org.cprover.CProver;
import java.lang.NullPointerException;
import java.lang.IllegalMonitorStateException;

public class Object {

    // lock needed for synchronization in JBMC
    // used by monitorenter, monitorexit, wait, and notify
    // Not present in the original Object class
    public int cproverMonitorCount;

    public Object() {
      cproverMonitorCount = 0;
    }

    /**
     * @diffblue.limitedSupport
     * This relies on Class.forName whose model is only partial. The model of
     * Class is made to work for combinations of calls to Object.getClass,
     * Class.forName and Class.getName but other operations are unlikely to
     * work.
     */
    public final Class<?> getClass() {
      // rskj trie verification: canonical Class objects (see header). Each listed class is final
      // or has no subclass on the classpath, so instanceof identifies the exact runtime class.
      if (this instanceof co.rsk.core.types.ints.Uint24) {
        return JbmcCanonicalClasses.UINT24;
      }
      if (this instanceof co.rsk.core.types.ints.Uint16) {
        return JbmcCanonicalClasses.UINT16;
      }
      if (this instanceof co.rsk.core.types.ints.Uint8) {
        return JbmcCanonicalClasses.UINT8;
      }
      if (this instanceof co.rsk.crypto.Keccak256) {
        return JbmcCanonicalClasses.KECCAK256;
      }
      if (this instanceof co.rsk.trie.Trie) {
        return JbmcCanonicalClasses.TRIE;
      }
      if (this instanceof org.ethereum.vm.DataWord) {
        return JbmcCanonicalClasses.DATAWORD;
      }
      if (this instanceof co.rsk.core.RskAddress) {
        // RskAddress has one subclass, the anonymous co.rsk.remasc.RemascTransaction$1 (the REMASC
        // address constant); it is mapped to RskAddress's Class. Harnesses never compare against it.
        return JbmcCanonicalClasses.RSKADDRESS;
      }
      if (this instanceof co.rsk.core.Coin) {
        return JbmcCanonicalClasses.COIN;
      }
      assert false : "Object model: getClass() on a class without a canonical Class object";
      return Class.forName(CProver.classIdentifier(this));
    }

    public int hashCode() {
      return 0;
    }

    public boolean equals(Object obj) {
        return (this == obj);
    }

    protected Object clone() throws CloneNotSupportedException {
      throw new CloneNotSupportedException();
    }

    public String toString() {
        return getClass().getName() + "@" + Integer.toHexString(hashCode());
    }

    public final void notify() {
      // TODO: the thread must own the lock when it calls notify
    }

    public final void notifyAll() {
      // TODO: the thread must own the lock when it calls notifyAll
    }

    public final void wait(long timeout) throws InterruptedException {
      // TODO: the thread must own the lock when it calls wait
      //       should only throw if the interrupted flag in Thread is enabled
      throw new InterruptedException();
    }

    public final void wait(long timeout, int nanos) throws InterruptedException {
        if (timeout < 0) {
            throw new IllegalArgumentException("timeout value is negative");
        }

        if (nanos < 0 || nanos > 999999) {
            throw new IllegalArgumentException(
                                "nanosecond timeout value out of range");
        }

        if (nanos > 0) {
            timeout++;
        }

        wait(timeout);
    }

    public final void wait() throws InterruptedException {
        wait(0);
    }

    protected void finalize() throws Throwable { }

    /**
     * This method is not present in the original Object class.
     * It will be called by JBMC when the monitor in this instance
     * is being acquired as a result of either the execution of a
     * monitorenter bytecode instruction or the call to a synchronized
     * method. It uses a counter to enable reentrance and an atomic section
     * to ensure multiple threads do not race in the access/modification of
     * the counter.
     */
    public static void monitorenter(Object object)
    {
      // TODO: we shoud remove the call to this method from the call
      //       stack appended to the thrown exception
      if (object == null)
          throw new NullPointerException();

      CProver.atomicBegin();
      // this assume blocks this execution path in JBMC and simulates
      // the thread having to wait because the monitor is not available
      CProver.assume(object.cproverMonitorCount == 0);
      object.cproverMonitorCount++;
      CProver.atomicEnd();
    }

    /**
     * This method is not present in the original Object class.
     * It will be called by JBMC when the monitor in this instance
     * is being released as a result of either the execution of a
     * monitorexit bytecode instruction or the return (normal or exceptional)
     * of a synchronized method. It decrements the cproverMonitorCount that
     * had been incremented in monitorenter().
     */
    public static void monitorexit(Object object)
    {
      // TODO: we shoud remove the call to this method from the call
      //       stack appended to the thrown exception
      // TODO: Enabling these exceptions makes
      //       jbmc/synchronized-blocks/test_sync.desc
      //       run into an infinite loop during symex
      // if (object == null)
      //   throw new NullPointerException();
      // if (object.cproverMonitorCount == 0)
      //   throw new IllegalMonitorStateException();
      CProver.atomicBegin();
      object.cproverMonitorCount--;
      CProver.atomicEnd();
    }
}
