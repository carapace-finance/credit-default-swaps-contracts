import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@solidstate/hardhat-bytecode-exporter";
import "@tenderly/hardhat-tenderly";
import "@typechain/ethers-v5";
import "@typechain/hardhat";
import "solidity-coverage";
import "@primitivefi/hardhat-dodoc";
import "dotenv/config";
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "hardhat-storage-layout";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-foundry";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import "hardhat-log-remover";

const {
  ALCHEMY_API_KEY,
  ETHERSCAN_API_KEY,
  MNEMONIC_WORDS,
  WALLET_INITIAL_INDEX,
  DEPLOYMENT_ACCOUNT_PRIVATE_KEY
} = process.env;

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
        // url: "https://mainnet.gateway.tenderly.co/6ZPssnDskim7cIosJXAHVs",
        // url: `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
        // 09/23/2022: We are pinning to this block number to avoid goldfinch pool & token position changes
        blockNumber: 15598870
      },
      gas: "auto", // gasLimit
      gasPrice: 259000000000, // check the latest gas price market in https://www.ethgasstation.info/
      // accounts are set at the end of this file
      // TODO: make this false once ProtectionPool size issue is fixed
      allowUnlimitedContractSize: true
    },
    localhost: {
      url: "http://0.0.0.0:8545"
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
      gas: "auto", // gasLimit
      gasPrice: 41000000000, // check the latest gas price market in https://www.ethgasstation.info/
      // inject: false, // optional. If true, it will EXPOSE your mnemonic in your frontend code. Then it would be available as an "in-page browser wallet" / signer which can sign without confirmation.
      accounts: [`0x${DEPLOYMENT_ACCOUNT_PRIVATE_KEY}`]
    }
  },
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000
      },
      outputSelection: {
        "*": {
          "*": ["storageLayout"]
        }
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 2000000
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY
  },
  dodoc: {
    runOnCompile: false,
    debugMode: true
  },
  gasReporter: {
    enabled: false
  },
  abiExporter: {
    flat: true,
    format: "json"
  },
  bytecodeExporter: {
    path: "./bytecode",
    flat: true
  }
};

if (
  config?.networks?.hardhat &&
  MNEMONIC_WORDS != undefined &&
  WALLET_INITIAL_INDEX != undefined
) {
  config.networks.hardhat.accounts = {
    mnemonic: MNEMONIC_WORDS,
    initialIndex: parseInt(WALLET_INITIAL_INDEX) // set index of account to use inside wallet (defaults to 0)
  };
}

/**
 * Task to start a local node using the localhost network configuration,
 * which is bound to hostname 0.0.0.0.
 * This custom task is needed because the in-built hardhat `node` task doesn't allow
 * to specify the network configuration to use with the `network` argument.
 */
task(
  "node-for-graph",
  "Starts a local node with the localhost network configuration with hostname bound to 0.0.0.0"
).setAction(async (args, hre: HardhatRuntimeEnvironment) => {
  // get localhost network config and mark it as default
  const localhostConfig = hre.config.networks.localhost;
  hre.config.networks.defaultNetwork = localhostConfig;

  // remove forking config from hardhat network config
  // so that local node doesn't fork from mainnet
  hre.config.networks.hardhat.forking = undefined;
  await hre.run("node", {
    network: "localhost",
    hostname: "0.0.0.0"
  });
});

export default config;
