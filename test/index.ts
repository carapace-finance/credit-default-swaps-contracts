import { testPool } from "./contracts/Pool.test";
import { testPoolFactory } from "./contracts/PoolFactory.test";
import { testPoolCycleManager } from "./contracts/PoolCycleManager.test";
import { testAccruedPremiumCalculator } from "./contracts/AccruedPremiumCalculator.test";
import { testRiskPremiumCalculator } from "./contracts/RiskPremiumCalculator.test";

import {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolInstance,
  poolFactoryInstance,
  riskPremiumCalculatorInstance,
  referenceLendingPoolsInstance,
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
        deployer,
        account1,
        poolFactoryInstance,
        riskPremiumCalculatorInstance,
        referenceLendingPoolsInstance
      );
    });

    it("run the PoolCycleManager test", async () => {
      testPoolCycleManager(deployer, account1, poolCycleManagerInstance);
    });

    it("run the AccruedPremiumCalculator test", async () => {
      testAccruedPremiumCalculator(accruedPremiumCalculatorInstance);
    });

    it("run the RiskPremiumCalculator test", async () => {
      testRiskPremiumCalculator(riskPremiumCalculatorInstance);
    });
  });
});
