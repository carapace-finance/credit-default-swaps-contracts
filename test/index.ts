import { testPool } from "./contracts/Pool.test";
import { testPoolFactory } from "./contracts/PoolFactory.test";
import { testPremiumPricing } from "./contracts/PremiumPricing.test";
import { testPoolCycleManager } from "./contracts/PoolCycleManager.test";
import { testAccruedPremiumCalculator } from "./contracts/AccruedPremiumCalculator.test";

import {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolInstance,
  poolFactoryInstance,
  premiumPricingInstance,
  referenceLoansInstance,
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance
} from "../utils/deploy";

describe("start testing", () => {
  before("deploy contracts", async () => {
    await deployContracts();
  });

  describe("run all the tests", () => {
    it("run the Pool test", async () => {
      testPool(deployer, account1, account2, account3, poolInstance);
    });

    it("run the PoolFactory test", async () => {
      testPoolFactory(
        account1,
        poolFactoryInstance,
        premiumPricingInstance,
        referenceLoansInstance
      );
    });

    it("run the PremiumPricing test", async () => {
      testPremiumPricing(premiumPricingInstance);
    });

    it("run the PoolCycleManager test", async () => {
      testPoolCycleManager(deployer, account1, poolCycleManagerInstance);
    });

    it("run the AccruedPremiumCalculator test", async () => {
      testAccruedPremiumCalculator(accruedPremiumCalculatorInstance);
    });
  });
});
