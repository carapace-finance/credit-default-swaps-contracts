import { deployAndSetup } from "./local-mainnet/deployAndSetup";

(async () => {
  // Deploy and setup contracts using mock contracts for GoldfinchAdapter and USDC
  // This script should only be run against a local hardhat node with localhost for local graph development
  await deployAndSetup(true);
})().catch((err) => {
  console.error(err);
});
