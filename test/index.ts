import { testPool } from "./contracts/Pool.test";
import { testPoolFactory } from "./contracts/PoolFactory.test";
import { testPremiumPricing } from "./contracts/PremiumPricing.test";
import { testTranche } from "./contracts/Tranche.test";
import { testTrancheFactory } from "./contracts/TrancheFactory.test";
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
  trancheInstance,
  trancheFactoryInstance,
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance
} from "../utils/deploy";

describe("start testing", () => {
  before("deploy contracts", async () => {
    await deployContracts();
  });

  describe("run all the tests", () => {
    it("run the Pool test", async () => {
      testPool(account1, poolInstance, referenceLoansInstance);
    });

    it("run the PoolFactory test", async () => {
      testPoolFactory(
        account1,
        poolFactoryInstance,
        premiumPricingInstance,
        referenceLoansInstance,
        trancheFactoryInstance
      );
    });

    it("run the PremiumPricing test", async () => {
      testPremiumPricing(premiumPricingInstance);
    });

    it("run the Tranche test", async () => {
      testTranche(
        deployer,
        account1,
        account2,
        account3,
        premiumPricingInstance,
        trancheInstance
      );
    });

    it("run the TrancheFactory test", async () => {
      testTrancheFactory(
        account1,
        poolInstance,
        trancheFactoryInstance,
        premiumPricingInstance,
        referenceLoansInstance,
        poolCycleManagerInstance
      );
    });
    
    it("run the PoolCycleManager test", async () => {
      testPoolCycleManager(
        deployer,
        account1,
        poolCycleManagerInstance
      );
    });

    it("run the AccruedPremiumCalculator test", async () => {
      testAccruedPremiumCalculator(
        accruedPremiumCalculatorInstance
      );
    });
  });
});
