import { testPool } from "./contracts/Pool.test";
import { testContractFactory } from "./contracts/ContractFactory.test";
import { testPoolCycleManager } from "./contracts/PoolCycleManager.test";
import { testAccruedPremiumCalculator } from "./contracts/AccruedPremiumCalculator.test";
import { testPremiumCalculator } from "./contracts/PremiumCalculator.test";
import { testRiskFactorCalculator } from "./contracts/RiskFactorCalculator.test";

import { testGoldfinchAdapter } from "./contracts/GoldfinchAdapter.test";
import { testReferenceLendingPools } from "./contracts/ReferenceLendingPools.test";
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
  cpContractFactoryInstance,
  premiumCalculatorInstance,
  referenceLendingPoolsInstance,
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance,
  riskFactorCalculatorInstance,
  goldfinchAdapterImplementation,
  goldfinchAdapterInstance,
  referenceLendingPoolsImplementation,
  defaultStateManagerInstance,
  GOLDFINCH_LENDING_POOLS,
  getLatestReferenceLendingPoolsInstance,
  getPoolContractFactory
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
      testPremiumCalculator(
        deployer,
        account1,
        premiumCalculatorInstance,
        riskFactorCalculatorInstance
      );
    });

    it("run the GoldfinchAdapter test", async () => {
      testGoldfinchAdapter(
        deployer,
        account1,
        goldfinchAdapterImplementation,
        goldfinchAdapterInstance
      );
    });

    it("run the ContractFactory test", async () => {
      testContractFactory(
        deployer,
        account1,
        cpContractFactoryInstance,
        premiumCalculatorInstance,
        referenceLendingPoolsInstance,
        poolCycleManagerInstance,
        defaultStateManagerInstance,
        poolImplementation,
        referenceLendingPoolsImplementation,
        getLatestReferenceLendingPoolsInstance
      );
    });

    it("Run ReferenceLendingPools test", async () => {
      testReferenceLendingPools(
        deployer,
        account1,
        referenceLendingPoolsImplementation,
        referenceLendingPoolsInstance,
        cpContractFactoryInstance,
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
        poolImplementation,
        referenceLendingPoolsInstance,
        poolCycleManagerInstance,
        defaultStateManagerInstance,
        getPoolContractFactory
      );
    });

    it("run DefaultStateManager test", async () => {
      testDefaultStateManager(
        deployer,
        account1,
        account3,
        defaultStateManagerInstance,
        cpContractFactoryInstance,
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
        cpContractFactoryInstance.address
      );
    });
  });
});
