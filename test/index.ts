import { testPool } from "./contracts/Pool.test";
import { testPoolFactory } from "./contracts/PoolFactory.test";
import { testPoolCycleManager } from "./contracts/PoolCycleManager.test";
import { testAccruedPremiumCalculator } from "./contracts/AccruedPremiumCalculator.test";
import { testPremiumCalculator } from "./contracts/PremiumCalculator.test";
import { testRiskFactorCalculator } from "./contracts/RiskFactorCalculator.test";

import { testGoldfinchAdapter } from "./contracts/GoldfinchAdapter.test";
import { testReferenceLendingPools } from "./contracts/ReferenceLendingPools.test";
import { testReferenceLendingPoolsFactory } from "./contracts/ReferenceLendingPoolsFactory.test";
import { testDefaultStateManager } from "./contracts/DefaultStateManager.test";

import {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolImplementation,
  poolInstance,
  poolFactoryInstance,
  premiumCalculatorInstance,
  referenceLendingPoolsInstance,
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance,
  riskFactorCalculatorInstance,
  goldfinchAdapterInstance,
  lendingProtocolAdapterFactoryInstance,
  referenceLendingPoolsFactoryInstance,
  referenceLendingPoolsImplementation,
  defaultStateManagerInstance,
  GOLDFINCH_LENDING_POOLS,
  getLatestReferenceLendingPoolsInstance,
  getLatestPoolInstance
} from "../utils/deploy";

describe("start testing", () => {
  before("deploy contracts", async () => {
    const start = Date.now();
    await deployContracts();
    console.log(`Deployed contracts in ${(Date.now() - start) / 1000} seconds`);
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
      testGoldfinchAdapter(goldfinchAdapterInstance);
    });

    it("run referenceLendingPoolsFactory test", async () => {
      testReferenceLendingPoolsFactory(
        deployer,
        account1,
        referenceLendingPoolsImplementation,
        referenceLendingPoolsFactoryInstance,
        lendingProtocolAdapterFactoryInstance,
        getLatestReferenceLendingPoolsInstance
      );
    });

    it("run the PoolFactory test", async () => {
      testPoolFactory(
        deployer,
        account1,
        poolFactoryInstance,
        premiumCalculatorInstance,
        referenceLendingPoolsInstance,
        poolCycleManagerInstance,
        defaultStateManagerInstance,
        poolImplementation
      );
    });

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

    it("run the Pool test", async () => {
      testPool(
        deployer,
        account1,
        account2,
        account3,
        account4,
        poolInstance,
        referenceLendingPoolsInstance,
        poolCycleManagerInstance,
        defaultStateManagerInstance
      );
    });

    it("run DefaultStateManager test", async () => {
      testDefaultStateManager(
        deployer,
        account1,
        account3,
        defaultStateManagerInstance,
        poolFactoryInstance,
        poolInstance,
        GOLDFINCH_LENDING_POOLS
      );
    });

    // Run this spec last because it moves time forward a lot and that impacts the pool tests
    it("run the PoolCycleManager test", async () => {
      testPoolCycleManager(
        deployer,
        account1,
        poolCycleManagerInstance,
        poolFactoryInstance.address
      );
    });
  });
});
