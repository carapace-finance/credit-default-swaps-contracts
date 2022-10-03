import { testPool } from "./contracts/Pool.test";
import { testPoolFactory } from "./contracts/PoolFactory.test";
import { testPoolCycleManager } from "./contracts/PoolCycleManager.test";
import { testAccruedPremiumCalculator } from "./contracts/AccruedPremiumCalculator.test";
import { testPremiumCalculator } from "./contracts/PremiumCalculator.test";
import { testRiskFactorCalculator } from "./contracts/RiskFactorCalculator.test";

import { testGoldfinchV2Adapter } from "./contracts/GoldfinchV2Adapter.test";
import { testReferenceLendingPools } from "./contracts/ReferenceLendingPools.test";
import { testReferenceLendingPoolsFactory } from "./contracts/ReferenceLendingPoolsFactory.test";

import {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolInstance,
  poolFactoryInstance,
  premiumCalculatorInstance,
  referenceLendingPoolsInstance,
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance,
  riskFactorCalculatorInstance,
  goldfinchV2AdapterInstance,
  referenceLendingPoolsFactoryInstance,
  referenceLendingPoolsImplementation,
  GOLDFINCH_LENDING_POOLS,
  getReferenceLendingPoolsInstanceFromTx
} from "../utils/deploy";

describe("start testing", () => {
  before("deploy contracts", async () => {
    await deployContracts();
  });

  describe("run all the tests", () => {
    it("run the RiskFactorCalculator test", async () => {
      testRiskFactorCalculator(riskFactorCalculatorInstance);
    });

    it("run the AccruedPremiumCalculator test", async () => {
      testAccruedPremiumCalculator(accruedPremiumCalculatorInstance);
    });

    it("run the PremiumCalculator test", async () => {
      testPremiumCalculator(premiumCalculatorInstance);
    });

    it("run the GoldfinchV2Adapter test", async () => {
      testGoldfinchV2Adapter(goldfinchV2AdapterInstance);
    });

    it("run referenceLendingPoolsFactory test", async () => {
      testReferenceLendingPoolsFactory(
        deployer,
        account1,
        referenceLendingPoolsImplementation,
        referenceLendingPoolsFactoryInstance,
        getReferenceLendingPoolsInstanceFromTx
      );
    });

    it("run the PoolFactory test", async () => {
      testPoolFactory(
        deployer,
        account1,
        poolFactoryInstance,
        premiumCalculatorInstance,
        referenceLendingPoolsInstance
      );
    });

    it("run the Pool test", async () => {
      testPool(
        deployer,
        account1,
        account2,
        account3,
        account4,
        poolInstance,
        GOLDFINCH_LENDING_POOLS
      );
    });

    // Run this spec last because it moves time forward a lot and that impacts the pool tests
    it("run the PoolCycleManager test", async () => {
      testPoolCycleManager(deployer, account1, poolCycleManagerInstance);
    });

    // This spec also moves time forward, so keep it last
    it("Run ReferenceLendingPools test", async () => {
      testReferenceLendingPools(
        deployer,
        account1,
        referenceLendingPoolsImplementation,
        referenceLendingPoolsInstance,
        referenceLendingPoolsFactoryInstance,
        GOLDFINCH_LENDING_POOLS
      );
    });
  });
});
