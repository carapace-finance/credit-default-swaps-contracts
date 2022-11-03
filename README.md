## Develop Locally

1. Clone this repo and npm install

```bash
$ git clone https://github.com/carapace-finance/credit-default-swaps-contracts
$ cd credit-default-swaps-contracts
$ npm install
```

2. Create an [Alchemy](https://www.alchemy.com/) or [Infura](https://infura.io/) account and get their api key.

3. Declare environment variables

I encourage you to declare environment variables in your `.bash_profile`(or .zprofile and others) to avoid sharing your credentials accidentally. You can also make `.env` file in the root of this repository although I do not recommend it.

```bash
export ALCHEMY_API_KEY = <alchemy_api_key>
export INFURA_API_KEY = <infura_api_key>
export TENDERLY_ETH_MAINNET_FORK_URL = <tenderly_fork_url>
export DEPLOYMENT_ACCOUNT_PRIVATE_KEY = <deployment_account_private_key>
export MNEMONIC_WORDS = <mnemonic_words>
export WALLET_INITIAL_INDEX = "0"
export ETHERSCAN_API_KEY = <etherscan_api_key>
export FIRST_POOL_SALT = <first_pool_salt>
export SECOND_POOL_SALT = <second_pool_salt>
```

I recommend obtaining your mnemonic words from MetaMask and storing in `MNEMONIC_WORDS` so that you can use the same account when you test a dapp. Each word should be divided by space. You can create a new private key for `DEPLOYMENT_ACCOUNT_PRIVATE_KEY`or export your private key in MetaMask.

You can keep `ETHERSCAN_API_KEY` empty until you deploy to the mainnet. Ask the team about salt values is when you create a new pool.

You are ready to write code!

## npm Script

```bash
$ npm run compile
// compiles your contracts and generate artifacts and cache.

$ npm run node
// runs the default network configured in the `hardhat.config.ts`.

$ npm run deploy:mainnet_forked
// deploys your contracts to the mirrored version of the mainnet in your local network.

$ npm run test
// runs test in the test directory.

$ npm run cover
// generate a code coverage report for testing.

$ npm run tenderly:verify
//

$ npm run tenderly:push
//

$ npm run doc
// generate a documentation from NatSpec comments.
```
