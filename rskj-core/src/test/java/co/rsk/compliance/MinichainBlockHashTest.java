package co.rsk.compliance;

import co.rsk.core.BlockDifficulty;
import co.rsk.core.Coin;
import co.rsk.core.RskAddress;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.typesafe.config.Config;
import com.typesafe.config.ConfigFactory;
import org.bouncycastle.util.encoders.Hex;
import org.ethereum.config.blockchain.upgrades.ActivationConfig;
import org.ethereum.core.BlockFactory;
import org.ethereum.core.BlockHeader;
import org.ethereum.core.BlockHeaderBuilder;
import org.ethereum.util.ByteUtil;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import static org.junit.jupiter.api.Assertions.assertEquals;

class MinichainBlockHashTest {

    private static final Path FIXTURE_PATH = resolveFixturePath();
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final Config MAINNET_CFG = ConfigFactory.load("config/main").getConfig("blockchain.config");
    private static final ActivationConfig ACTIVATIONS = ActivationConfig.read(MAINNET_CFG);
    private static final BlockFactory BLOCK_FACTORY = new BlockFactory(ACTIVATIONS);

    @Test
    void recomputesMiniChainHashes() throws Exception {
        JsonNode root = MAPPER.readTree(Files.readAllBytes(FIXTURE_PATH));
        JsonNode chain = root.get("chain");

        for (JsonNode entry : chain) {
            JsonNode h = entry.get("header");
            String expected = entry.get("expectedHash").asText();

            BlockHeader header = buildHeader(h);
            String computed = "0x" + ByteUtil.toHexString(header.getHash().getBytes());

            assertEquals(expected.toLowerCase(), computed.toLowerCase(),
                    () -> "hash mismatch for " + entry.get("tag").asText());
        }
    }

    private static BlockHeader buildHeader(JsonNode h) {
        BlockHeaderBuilder builder = BLOCK_FACTORY.getBlockHeaderBuilder()
                .setParentHash(bytes(h, "parentHash"))
                .setUnclesHash(bytes(h, "unclesHash"))
                .setCoinbase(new RskAddress(bytes(h, "coinbase")))
                .setStateRoot(bytes(h, "stateRoot"))
                .setTxTrieRoot(bytes(h, "transactionsRoot"))
                .setReceiptTrieRoot(bytes(h, "receiptsRoot"))
                .setLogsBloom(bytes(h, "logsBloom"))
                .setDifficulty(new BlockDifficulty(bigInt(h, "difficulty")))
                .setNumber(longHex(h, "number"))
                .setGasLimit(bytes(h, "gasLimit"))
                .setGasUsed(longHex(h, "gasUsed"))
                .setTimestamp(longHex(h, "timestamp"))
                .setExtraData(bytes(h, "extraData"))
                .setPaidFees(new Coin(bigInt(h, "paidFees")))
                .setMinimumGasPrice(new Coin(bigInt(h, "minimumGasPrice")))
                .setUncleCount(intHex(h, "uncleCount"))
                .setBitcoinMergedMiningHeader(bytes(h, "bitcoinMergedMiningHeader"))
                .setBitcoinMergedMiningMerkleProof(bytes(h, "bitcoinMergedMiningMerkleProof"))
                .setBitcoinMergedMiningCoinbaseTransaction(bytes(h, "bitcoinMergedMiningCoinbaseTransaction"));

        return builder.build();
    }

    private static Path resolveFixturePath() {
        Path[] candidates = new Path[] {
                Paths.get("compliance", "fixtures", "blockhash-mini-chain.json"),
                Paths.get("..", "compliance", "fixtures", "blockhash-mini-chain.json")
        };

        for (Path candidate : candidates) {
            if (Files.exists(candidate)) {
                return candidate;
            }
        }

        throw new IllegalStateException("No se encontró compliance/fixtures/blockhash-mini-chain.json");
    }

    private static byte[] bytes(JsonNode h, String field) {
        return bytes(h.get(field).asText());
    }

    private static byte[] bytes(String hex) {
        String clean = hex.startsWith("0x") ? hex.substring(2) : hex;
        if (clean.isEmpty()) {
            return new byte[0];
        }
        if ((clean.length() & 1) == 1) {
            clean = "0" + clean;
        }
        return Hex.decode(clean);
    }

    private static BigInteger bigInt(JsonNode h, String field) {
        return bigInt(h.get(field).asText());
    }

    private static BigInteger bigInt(String hex) {
        String clean = hex.startsWith("0x") ? hex.substring(2) : hex;
        if (clean.isEmpty()) {
            return BigInteger.ZERO;
        }
        return new BigInteger(clean, 16);
    }

    private static int intHex(JsonNode h, String field) {
        return intHex(h.get(field).asText());
    }

    private static int intHex(String hex) {
        String clean = hex.startsWith("0x") ? hex.substring(2) : hex;
        if (clean.isEmpty()) {
            return 0;
        }
        return (int) Long.parseLong(clean, 16);
    }

    private static long longHex(JsonNode h, String field) {
        return longHex(h.get(field).asText());
    }

    private static long longHex(String hex) {
        String clean = hex.startsWith("0x") ? hex.substring(2) : hex;
        if (clean.isEmpty()) {
            return 0;
        }
        return new BigInteger(clean, 16).longValueExact();
    }
}
