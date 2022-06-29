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
export DEPLOYMENT_ACCOUNT_PRIVATE_KEY = <deployment_account_private_key>
export MNEMONIC_WORDS = <mnemonic_words>
export WALLET_INITIAL_INDEX = "0"
export ETHERSCAN_API_KEY = <etherscan_api_key>
export FIRST_POOL_SALT = <first_pool_salt>
```

You can leave `DEPLOYMENT_ACCOUNT_PRIVATE_KEY` and `ETHERSCAN_API_KEY` empty until you deploy to the mainnet. I recommend obtaining your mnemonic words from MetaMask and storing in `MNEMONIC_WORDS`so that you can use the same account when you test a dapp. Ask the team what the `FIRST_POOL_SALT` is when you create a new pool. 

You are ready to write code!

## npm Script

```
$ npm run compile
// compiles your contracts and generate artifacts and cache.

$ npm run deploy:mainnet_forked
// deploys your contracts to the mirrored version of the mainnet in your local network.

$ npm run node
// runs the default network configured in the `hardhat.config.ts`.

$ npm run test
// runs test in the test directory.

$ npm run cover
// generate a code coverage report for testing.
$ npm run doc
// generate a documentation from NatSpec comments.
```
