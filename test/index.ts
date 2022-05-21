import { tranche } from "./contracts/Tranche.test";
import { premiumPricing } from "./contracts/PremiumPricing.test";
import {
  deployer,
  account1,
  deployContracts,
  trancheInstance,
  premiumPricingInstance
} from "../utils/deploy";

describe("start testing", () => {
  it("deploy contracts", async () => {
    await deployContracts();
  });

  it("run all the tests", () => {
    tranche(deployer, account1, premiumPricingInstance, trancheInstance);
    premiumPricing(deployer, premiumPricingInstance);
  });
});
