import { tranche } from "./contracts/Tranche.test";
import { premiumPricing } from "./contracts/PremiumPricing.test";
import {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  trancheInstance,
  premiumPricingInstance
} from "../utils/deploy";

describe("start testing", () => {
  it("deploy contracts", async () => {
    await deployContracts();
  });

  it("run all the tests", () => {
    tranche(
      deployer,
      account1,
      account2,
      account3,
      premiumPricingInstance,
      trancheInstance
    );
    premiumPricing(deployer, premiumPricingInstance);
  });
});
