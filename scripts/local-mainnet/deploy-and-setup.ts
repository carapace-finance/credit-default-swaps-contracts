import { deployAndSetup } from "./deployAndSetup";

(async () => {
  // Deploy and setup contracts using all real contracts
  // This script can only be run against a local hardhat node with mainnet fork
  await deployAndSetup(false);
})().catch((err) => {
  console.error(err);
});
