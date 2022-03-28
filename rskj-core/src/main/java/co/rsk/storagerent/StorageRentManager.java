package co.rsk.storagerent;

import co.rsk.util.HexUtils;
import com.google.common.annotations.VisibleForTesting;
import org.ethereum.core.Repository;
import org.ethereum.db.TrackedNode;
import org.ethereum.vm.GasCost;
import org.ethereum.vm.program.Program;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * StorageRentManager, responsible for paying StorageRent (RSKIP240)
 * https://github.com/rsksmart/RSKIPs/blob/master/IPs/RSKIP240.md
 * */
public class StorageRentManager {
    private static final Logger LOGGER_FEDE = LoggerFactory.getLogger("fede");

    public static final long NO_ROLLBACK_RENT_YET = -1;
    private static final long NO_PAYABLE_RENT_YET = -1;
    private static final long NO_TOTAL_RENT_YET = -1;

    private Set<RentedNode> rentedNodes = Collections.emptySet();
    private List<RentedNode> rollbackNodes = Collections.emptyList();

    // todo(fedejinich) this fields are unnecessary for production, but good for testing
    //  they will be removed before merging into master
    private long rollbacksRent;
    private long payableRent;
    private long totalRent;

    public StorageRentManager() {
        this.rollbacksRent = NO_ROLLBACK_RENT_YET;
        this.payableRent = NO_PAYABLE_RENT_YET;
        this.totalRent = NO_TOTAL_RENT_YET;
    }

    /**
     * Pay storage rent.
     *
     * @param gasRemaining remaining gas amount to pay storage rent
     * @param executionBlockTimestamp execution block timestamp
     * @param blockTrack repository to fetch the relevant data before the transaction execution
     * @param transactionTrack repository to update the rent timestamps
     *
     * @return new remaining gas
     * */
    public long pay(long gasRemaining, long executionBlockTimestamp,
                    Repository blockTrack, Repository transactionTrack,
                    String transactionHash) {
        Set<TrackedNode> storageRentNodes = new HashSet<>();
        blockTrack.getStorageRentNodes(transactionHash).forEach(trackedNode -> storageRentNodes.add(trackedNode));
        transactionTrack.getStorageRentNodes(transactionHash).forEach(trackedNode -> storageRentNodes.add(trackedNode));

        List<TrackedNode> rollbackNodes = new ArrayList<>();
        blockTrack.getRollBackNodes(transactionHash).stream()
                .filter(r -> r.useForStorageRent())
                .forEach(rollBackNode -> rollbackNodes.add(rollBackNode));
        transactionTrack.getRollBackNodes(transactionHash).stream()
                .filter(r -> r.useForStorageRent())
                .forEach(rollBackNode -> rollbackNodes.add(rollBackNode));

        if(storageRentNodes.isEmpty() && rollbackNodes.isEmpty()) {
            // todo(fedejinich) is this the right way to throw this exception
            throw new RuntimeException("there should be rented nodes or rollback nodes");
        }

        // LOGGER_FEDE.error("calculating payableRent and rollbacksRent");

        this.rentedNodes = storageRentNodes.stream()
                .map(trackedNode -> blockTrack.getRentedNode(trackedNode))
                .filter(rentedNode -> rentedNode.getSuccessful())
                .collect(Collectors.toSet());
        this.rollbackNodes = rollbackNodes.stream()
                .map(trackedNode -> blockTrack.getRentedNode(trackedNode))
                .collect(Collectors.toList());

        long payableRent = rentBy(this.rentedNodes,
                rentedNode -> rentedNode.payableRent(executionBlockTimestamp));
        long rollbacksRent = rentBy(this.rollbackNodes,
                rentedNode -> rentedNode.rollbackFee(executionBlockTimestamp));

        // LOGGER_FEDE.error("payableRent: {}, rollbacksRent: {}", payableRent, rollbacksRent);

        this.totalRent = payableRent + rollbacksRent;

        // LOGGER_FEDE.error("gasRemaining({}) < totalRent({})", gasRemaining, this.totalRent);

        if(gasRemaining < totalRent) {
            // todo(fedejinich) this is not the right way to throw an OOG
            throw new Program.OutOfGasException("not enough gasRemaining to pay storage rent. " +
                    "gasRemaining: " + gasRemaining + ", gasNeeded: " + totalRent);
        }

        // LOGGER_FEDE.error("executionBlockTimestamp: {}", executionBlockTimestamp);

        // LOGGER_FEDE.error("-- UPDATING RENT TIMESTAMPS --");

        // LOGGER_FEDE.error("rents to update: {}", this.rentedNodes);

        transactionTrack.updateRents(this.rentedNodes, executionBlockTimestamp);

        this.payableRent = payableRent;
        this.rollbacksRent = rollbacksRent;

        // LOGGER_FEDE.error("storage rent has been paid - paidRent: {}, payableRent: {}, rollbacksRent: {}", getPaidRent(), this.payableRent, this.rollbacksRent);

        return GasCost.subtract(gasRemaining, getPaidRent());
    }

    private long rentBy(Collection<RentedNode> rentedNodes, Function<RentedNode, Long> rentFunction) {
        return rentedNodes.isEmpty() ? 0 : rentedNodes.stream()
            .map(r -> rentFunction.apply(r))
            .reduce(GasCost::add)
            .get();
    }

    @VisibleForTesting
    public long getPaidRent() {
        if(this.payableRent == NO_PAYABLE_RENT_YET ||
                this.rollbacksRent == NO_ROLLBACK_RENT_YET || this.totalRent == NO_TOTAL_RENT_YET) {
            throw new RuntimeException("should pay rent before querying paid rent");
        }

        return this.totalRent;
    }

    @VisibleForTesting
    public long getPayableRent() {
        return payableRent;
    }

    @VisibleForTesting
    public long getRollbacksRent() {
        return this.rollbacksRent;
    }

    @VisibleForTesting
    public Set<RentedNode> getRentedNodes() {
        return this.rentedNodes;
    }

    @VisibleForTesting
    public List<RentedNode> getRollbackNodes() {
        return this.rollbackNodes;
    }

    // todo(fedejinich) this is for debugging
    private String printableKey(RentedNode node) {
        String s = HexUtils.toJsonHex(node.getKey().getData());
        return s.substring(s.length() - 5);
    }
}
