/*
 * This file is part of RskJ
 * Copyright (C) 2017 RSK Labs Ltd.
 * (derived from ethereumJ library, Copyright (c) 2016 <ether.camp>)
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

package co.rsk.storagerent;


// todo(fedejinich) this class can be moved into StorageRent

import co.rsk.trie.Trie;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.TimeUnit;

/**
 * Rent computation util according to the RSKIP240
 * https://github.com/rsksmart/RSKIPs/blob/master/IPs/RSKIP240.md
 */
public class StorageRentComputation {
    private static final Logger LOGGER_FEDE = LoggerFactory.getLogger("fede");

    public static final long READ_THRESHOLD = 2500;
    public static final long READ_THRESHOLD_CONTRACT_CODE = 15000;
    public static final long WRITE_THRESHOLD = 1000;
    public static final long RENT_CAP = 5000;
    public static final long RENT_CAP_CONTRACT_CODE = 30000;

    private static final double RENTAL_RATE = (1 / Math.pow(2, 21));
    private static final long STORAGE_OVERHEAD = 128;

    private StorageRentComputation() {}

    /**
     * Computes the amount of rent to be paid for trie reads/writes.
     * The final amount it's determined by the rent cap and rent threshold
     *
     * @param rentDue       a rent due
     * @param rentCap       a maximum gas amount to be pay
     * @param rentThreshold a gas threshold
     * @return an amount of gas to be paid
     */
    public static long computeRent(long rentDue, long rentCap, long rentThreshold) {
        validateArgumentsComputeRent(rentCap, rentThreshold);

        long computedRent = Math.min(rentCap, rentDue);

        // LOGGER_FEDE.error("min(rentCap: {}, rentDue: {}) = {}", rentCap, rentDue, computedRent);

        boolean b = computedRent > rentThreshold;

        // LOGGER_FEDE.error("computedRent({}) > rentThreshold({}). pays rent ? {}", computedRent, rentThreshold, b);

        return b ? computedRent : 0;
    }

    /**
     * Calculates the total rent due.
     * This is not the actual rent to be paid within a transaction because it's then limited by the rent cap.
     *
     * @param nodeSize a node value length (expressed in bytes)
     * @param duration a duration from the last paid time (expressed in milliseconds)
     * @return total rent due (gas amount)
     */
    // todo(fedejinich) this should be a private method, it's only used in computeRent & computeNewTimestamp
    public static long rentDue(long nodeSize, long duration) {
        validateArgumentsRentDue(nodeSize, duration);
        long nodeSizeWithOverhead = nodeSize + STORAGE_OVERHEAD;

        // LOGGER_FEDE.error("received this duration {}", duration);

        // todo(fedejinich) check time units
        Double aDouble = Double.valueOf(nodeSizeWithOverhead);
        Double aDouble1 = Double.valueOf(TimeUnit.MILLISECONDS.toSeconds(duration));
        Double result = Math.floor(aDouble * aDouble1 * RENTAL_RATE);

        // LOGGER_FEDE.error("rentDue = Math.floor({} * {} * {}) = {}", aDouble, aDouble1, RENTAL_RATE, result);

        return result.longValue();
    }

    /**
     * Computes the new timestamp after paying the rent or not.
     * If the rent exceeds the cap, it partially advances the last paid time.
     *
     * @param nodeSize a node size (expressed in bytes)
     * @param rentDue rent due (gas)
     * @param lastPaidTimestamp a timestamp corresponding to the last rent payment (expressed in seconds)
     * @param currentBlockTimestamp the current block timestamp
     * @param rentCap a gas cap (useful to partially advance the timestamp)
     * @param rentThreshold a gas threshold
     *
     * @return the new timestamp (it can be the same if it doesn't reach the threshold)
     * */
    public static long computeNewTimestamp(long nodeSize, long rentDue, long lastPaidTimestamp,
                                           long currentBlockTimestamp, long rentCap, long rentThreshold) {
        validateArgumentsComputeTimestamp(nodeSize, rentDue, lastPaidTimestamp, currentBlockTimestamp,
                rentCap, rentThreshold);

        if(lastPaidTimestamp == Trie.NO_RENT_TIMESTAMP) {
            // LOGGER_FEDE.error("this node is not timestamped yet, " + "giving the currentBlockTimestamp. oldTimestamp: {}, newTimestamp: {}", lastPaidTimestamp, currentBlockTimestamp);
            return currentBlockTimestamp;
        }

        if (rentDue <= rentThreshold) {
            // LOGGER_FEDE.error("this node is below the threshold, keeping the same timestamp: {}", lastPaidTimestamp);
            return lastPaidTimestamp;
        }

        if (rentDue <= rentCap) {
            // LOGGER_FEDE.error("this node is below the rentCap but above the threshold, " + "giving the currentBlockTimestamp. oldTimestamp: {}, newTimestamp: {}", lastPaidTimestamp, currentBlockTimestamp);
            return currentBlockTimestamp;
        }

        // partially advances the timestamp if rent due exceeds cap
        Double timePaid = Math.floor(rentCap / (nodeSize * RENTAL_RATE));
        long l = lastPaidTimestamp + timePaid.longValue();

        // LOGGER_FEDE.error("this node exceeds the rentCap, partially advancing the timestamp. " + "oldTimestamp: {}, newPartiallyAdvancedTimestamp: {}", lastPaidTimestamp, l);

        return l;
    }

    private static void validateArgumentsComputeTimestamp(long nodeSize, long rentDue, long lastPaidTimestamp,
                                                          long currentBlockTimestamp, long rentCap,
                                                          long rentThreshold) {
        validPositiveValue(nodeSize, "nodeSize must be positive");
        validPositiveValue(rentDue, "rentDue must be positive");
//        validPositiveValue(lastPaidTimestamp, "lastPaidTime must be positive"); // todo(fedejinich) not always. new created nodes or nodes < Hop contains -1
        validPositiveValue(currentBlockTimestamp, "currentBlockTimestamp must be positive");
        validPositiveValue(rentCap, "rentCap must be positive");
        validPositiveValue(rentThreshold, "rentThreshold must be positive");
    }

    private static void validateArgumentsRentDue(long nodeSize, long duration) {
        validPositiveValue(nodeSize, "node size must be positive");
        validPositiveValue(duration, "duration must be positive");
    }

    private static void validateArgumentsComputeRent(long cap, long threshold) {
        validPositiveValue(cap, "cap must be positive");
        validPositiveValue(threshold, "threshold must be positive");
    }

    private static void validPositiveValue(long value, String s) {
        if (value < 0) {
            throw new IllegalArgumentException(s);
        }
    }
}
