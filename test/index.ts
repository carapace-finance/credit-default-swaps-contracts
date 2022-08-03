import { pool } from "./contracts/Pool.test";
import { poolFactory } from "./contracts/PoolFactory.test";
import { premiumPricing } from "./contracts/PremiumPricing.test";
import { tranche } from "./contracts/Tranche.test";
import { trancheFactory } from "./contracts/TrancheFactory.test";
import { testPoolCycleManager } from "./contracts/PoolCycleManager.test";

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
  poolCycleManagerInstance
} from "../utils/deploy";

describe("start testing", () => {
  before("deploy contracts", async () => {
    await deployContracts();
  });

  describe("run all the tests", () => {
    it("run the Pool test", async () => {
      pool(account1, poolInstance, referenceLoansInstance);
    });

    it("run the PoolFactory test", async () => {
      poolFactory(
        account1,
        poolFactoryInstance,
        premiumPricingInstance,
        referenceLoansInstance,
        trancheFactoryInstance
      );
    });

    it("run the PremiumPricing test", async () => {
      premiumPricing(premiumPricingInstance);
    });

    it("run the Tranche test", async () => {
      tranche(
        deployer,
        account1,
        account2,
        account3,
        premiumPricingInstance,
        trancheInstance
      );
    });

    it("run the TrancheFactory test", async () => {
      trancheFactory(
        account1,
        trancheFactoryInstance,
        premiumPricingInstance,
        referenceLoansInstance
      );
    });
    
    it("run the PoolCycleManager test", async () => {
      testPoolCycleManager(
        deployer,
        account1,
        poolCycleManagerInstance
      );
    });
  });
});
