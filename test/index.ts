import { testPool } from "./contracts/Pool.test";
import { testPoolFactory } from "./contracts/PoolFactory.test";
import { testPoolCycleManager } from "./contracts/PoolCycleManager.test";
import { testAccruedPremiumCalculator } from "./contracts/AccruedPremiumCalculator.test";
import { testPremiumCalculator } from "./contracts/PremiumCalculator.test";
import { testRiskFactorCalculator } from "./contracts/RiskFactorCalculator.test";

import { testGoldfinchV2Adapter } from "./contracts/GoldfinchV2Adapter.test";
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
  defaultStateManagerInstance,
  GOLDFINCH_LENDING_POOLS,
  getReferenceLendingPoolsInstanceFromTx,
  getPoolInstanceFromTx
} from "../utils/deploy";
import { ethers } from "hardhat";
import { PoolCycleManager } from "../typechain-types/contracts/core/PoolCycleManager";

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
      const poolCycleManager = (await ethers.getContractAt(
        "PoolCycleManager",
        await poolFactoryInstance.getPoolCycleManager()
      )) as PoolCycleManager;

      testPool(
        deployer,
        account1,
        account2,
        account3,
        account4,
        poolInstance,
        referenceLendingPoolsInstance,
        poolCycleManager,
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
      testPoolCycleManager(deployer, account1, poolCycleManagerInstance);
    });
  });
});
