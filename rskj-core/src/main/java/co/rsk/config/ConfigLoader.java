/*
 * This file is part of RskJ
 * Copyright (C) 2018 RSK Labs Ltd.
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
package co.rsk.config;

import co.rsk.cli.CliArgs;
import com.typesafe.config.*;
import org.ethereum.config.SystemProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.annotation.Nullable;
import java.io.File;
import java.util.Map;
import java.util.Objects;

/**
 * Loads configurations from different sources with the following precedence:
 * 1. Command line arguments
 * 2. Environment variables
 * 3. System properties
 * 4. User configuration file
 * 5. Installer configuration file
 * 6. Default settings per network in resources/[network].conf
 * 7. Default settings for all networks in resources/reference.conf
 */
public class ConfigLoader {

    private static final Logger logger = LoggerFactory.getLogger("config");

    private static final String MAINNET_RESOURCE_PATH = "config/main";
    private static final String TESTNET_RESOURCE_PATH = "config/testnet";
    private static final String REGTEST_RESOURCE_PATH = "config/regtest";
    private static final String DEVNET_RESOURCE_PATH = "config/devnet";
    private static final String REFERENCE_RESOURCE_PATH = "reference";
    private static final String YES = "yes";
    private static final String NO = "no";

    private final CliArgs<NodeCliOptions, NodeCliFlags> cliArgs;

    public ConfigLoader(CliArgs<NodeCliOptions, NodeCliFlags> cliArgs) {
        this.cliArgs = Objects.requireNonNull(cliArgs);
    }

    public Config getConfig() {
        Config cliConfig = getConfigFromCliArgs();
        Config systemPropsConfig = ConfigFactory.systemProperties();
        Config systemEnvConfig = ConfigFactory.systemEnvironment();
        Config userCustomConfig = getUserCustomConfig();
        Config installerConfig = getInstallerConfig();

        Config userConfig = ConfigFactory.empty()
                .withFallback(cliConfig)
                .withFallback(systemPropsConfig)
                .withFallback(systemEnvConfig)
                .withFallback(userCustomConfig)
                .withFallback(installerConfig);
        Config networkBaseConfig = getNetworkDefaultConfig(userConfig);
        Config unifiedConfig = userConfig.withFallback(networkBaseConfig);

        if (unifiedConfig.getBoolean(SystemProperties.PROPERTY_BC_VERIFY)) {
            Config referenceConfig = ConfigFactory.load(REFERENCE_RESOURCE_PATH);
            ConfigObject expectedValue = referenceConfig.root();
            ConfigObject actualValue = ConfigFactory.empty()
                    .withFallback(cliConfig)
                    .withFallback(userCustomConfig)
                    .withFallback(installerConfig)
                    .withFallback(networkBaseConfig)
                    .root();
            verify("", expectedValue, actualValue);
        }

        return unifiedConfig;
    }

    private Config getConfigFromCliArgs() {
        Config config = ConfigFactory.empty();

        for (NodeCliFlags flag : cliArgs.getFlags()) {
            config = flag.withConfig(config);
        }

        for (Map.Entry<NodeCliOptions, String> entry : cliArgs.getOptions().entrySet()) {
            config = entry.getKey().withConfig(config, entry.getValue());
        }

        return config;
    }

    private Config getUserCustomConfig() {
        String file = System.getProperty("rsk.conf.file");
        Config cmdLineConfigFile = file != null ? ConfigFactory.parseFile(new File(file)) : ConfigFactory.empty();
        logger.info(
                "Config ( {} ): user properties from -Drsk.conf.file file '{}'",
                cmdLineConfigFile.entrySet().isEmpty() ? NO : YES,
                file
        );
        return cmdLineConfigFile;
    }

    private Config getInstallerConfig() {
        File installerFile = new File("/etc/rsk/node.conf");
        Config installerConfig = installerFile.exists() ? ConfigFactory.parseFile(installerFile) : ConfigFactory.empty();
        logger.info(
                "Config ( {} ): default properties from installer '/etc/rsk/node.conf'",
                installerConfig.entrySet().isEmpty() ? NO : YES
        );
        return installerConfig;
    }

    /**
     * @return the network-specific configuration based on the user config, or mainnet if no configuration is specified.
     */
    private Config getNetworkDefaultConfig(Config userConfig) {
        if (userConfig.hasPath(SystemProperties.PROPERTY_BC_CONFIG_NAME)) {
            String network = userConfig.getString(SystemProperties.PROPERTY_BC_CONFIG_NAME);
            if (NodeCliFlags.NETWORK_TESTNET.getName().equals(network)) {
                return ConfigFactory.load(TESTNET_RESOURCE_PATH);
            } else if (NodeCliFlags.NETWORK_REGTEST.getName().equals(network)) {
                return ConfigFactory.load(REGTEST_RESOURCE_PATH);
            } else if (NodeCliFlags.NETWORK_DEVNET.getName().equals(network)) {
                return ConfigFactory.load(DEVNET_RESOURCE_PATH);
            } else if (NodeCliFlags.NETWORK_MAINNET.getName().equals(network)) {
                return ConfigFactory.load(MAINNET_RESOURCE_PATH);
            } else {
                String exceptionMessage = String.format(
                        "%s is not a valid network name (%s property)",
                        network,
                        SystemProperties.PROPERTY_BC_CONFIG_NAME
                );
                logger.warn(exceptionMessage);
                throw new IllegalArgumentException(exceptionMessage);
            }
        }

        logger.info("Network not set, using mainnet by default");
        return ConfigFactory.load(MAINNET_RESOURCE_PATH);
    }

    private static void verify(String key, @Nullable ConfigValue expectedValue, ConfigValue actualValue) {
        if (expectedValue == null) {
            throw unexpectedKeyException(key, actualValue);
        }

        switch (actualValue.valueType()) {
            case OBJECT:
                if (!expectedValue.valueType().equals(ConfigValueType.OBJECT)) {
                    throw typeMismatchException(key, expectedValue, actualValue);
                }
                for (Map.Entry<String, ConfigValue> actualEntry : ((ConfigObject) actualValue).entrySet()) {
                    ConfigValue expectedEntryValue = ((ConfigObject) expectedValue).get(actualEntry.getKey());
                    verify((key.isEmpty() ? "" : key + ".") + actualEntry.getKey(), expectedEntryValue, actualEntry.getValue());
                }
                break;
            case LIST:
                if (!expectedValue.valueType().equals(ConfigValueType.LIST)) {
                    throw typeMismatchException(key, expectedValue, actualValue);
                }
                ConfigList actualList = (ConfigList) actualValue;
                ConfigList expectedList = (ConfigList) expectedValue;
                if (!actualList.isEmpty() && !expectedList.isEmpty()) {
                    // Assuming that all items in a list should have the same configuration structure.
                    ConfigValue expectedItem = expectedList.get(0);
                    int index = 0;
                    for (ConfigValue actualItem : actualList) {
                        verify(key + "[" + index + "]", expectedItem, actualItem);
                        index++;
                    }
                }
                break;
            default:
                if (expectedValue.valueType().equals(ConfigValueType.OBJECT) || expectedValue.valueType().equals(ConfigValueType.LIST)) {
                    throw typeMismatchException(key, expectedValue, actualValue);
                }
                break;
        }
    }

    private static IllegalArgumentException unexpectedKeyException(String key, ConfigValue actualValue) {
        return new IllegalArgumentException("Unexpected config value " + actualValue + " for key " + key);
    }

    private static IllegalArgumentException typeMismatchException(String key, ConfigValue expectedValue, ConfigValue actualValue) {
        return new IllegalArgumentException("Config value type mismatch. " + key + " has type " + actualValue.valueType()
                + ", but should have : " + expectedValue.valueType());
    }
}
