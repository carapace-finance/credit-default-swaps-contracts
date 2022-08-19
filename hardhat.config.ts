import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@tenderly/hardhat-tenderly";
import "@typechain/ethers-v5";
import "@typechain/hardhat";
import "solidity-coverage";
import "@primitivefi/hardhat-dodoc";
import "dotenv/config";
import "hardhat-contract-sizer";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`
        // url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
        // blockNumber: 14961117 // use the same block number to make subsequent runs faster with cache.
      },
      gas: "auto", // gasLimit
      gasPrice: 259000000000, // check the latest gas price market in https://www.ethgasstation.info/
      // inject: false, // optional. If true, it will EXPOSE your mnemonic in your frontend code. Then it would be available as an "in-page browser wallet" / signer which can sign without confirmation.
      accounts: {
        mnemonic: process.env.MNEMONIC_WORDS,
        initialIndex: process.env.WALLET_INITIAL_INDEX
          ? parseInt(process.env.WALLET_INITIAL_INDEX)
          : 0 // set index of account to use inside wallet (defaults to 0)
      },
      allowUnlimitedContractSize: false
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      // url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
      gas: "auto", // gasLimit
      gasPrice: 41000000000, // check the latest gas price market in https://www.ethgasstation.info/
      // inject: false, // optional. If true, it will EXPOSE your mnemonic in your frontend code. Then it would be available as an "in-page browser wallet" / signer which can sign without confirmation.
      accounts: [`0x${process.env.DEPLOYMENT_ACCOUNT_PRIVATE_KEY}`]
    }
  },
  solidity: {
    version: "0.8.13",
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
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  dodoc: {
    runOnCompile: false,
    debugMode: true
  }
};

export default config;
