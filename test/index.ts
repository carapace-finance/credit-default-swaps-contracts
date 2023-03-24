import { testProtectionPool } from "./contracts/ProtectionPool.test";
import { testContractFactory } from "./contracts/ContractFactory.test";
import { testProtectionPoolCycleManager } from "./contracts/ProtectionPoolCycleManager.test";
import { testAccruedPremiumCalculator } from "./contracts/AccruedPremiumCalculator.test";
import { testPremiumCalculator } from "./contracts/PremiumCalculator.test";
import { testRiskFactorCalculator } from "./contracts/RiskFactorCalculator.test";

import { testGoldfinchAdapter } from "./contracts/GoldfinchAdapter.test";
import { testReferenceLendingPools } from "./contracts/ReferenceLendingPools.test";
import { testDefaultStateManager } from "./contracts/DefaultStateManager.test";

import {
  deployer,
  operator,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  protectionPoolImplementation,
  protectionPoolInstance,
  cpContractFactoryInstance,
  premiumCalculatorInstance,
  referenceLendingPoolsInstance,
  protectionPoolCycleManagerInstance,
  accruedPremiumCalculatorInstance,
  riskFactorCalculatorInstance,
  goldfinchAdapterImplementation,
  goldfinchAdapterInstance,
  referenceLendingPoolsImplementation,
  defaultStateManagerInstance,
  getLatestReferenceLendingPoolsInstance,
  getProtectionPoolContractFactory
} from "../utils/deploy";

import {
  PROTECTION_POOL_CYCLE_PARAMS,
  PROTECTION_POOL_PARAMS,
  GOLDFINCH_LENDING_POOLS,
  LENDING_POOL_PROTOCOLS,
  LENDING_POOL_PURCHASE_LIMIT_IN_DAYS
} from "./test-data";

describe("start testing", () => {
  before("deploy contracts", async () => {
    const start = Date.now();
    await deployContracts(
      PROTECTION_POOL_CYCLE_PARAMS,
      PROTECTION_POOL_PARAMS,
      GOLDFINCH_LENDING_POOLS,
      LENDING_POOL_PROTOCOLS,
      LENDING_POOL_PURCHASE_LIMIT_IN_DAYS
    );
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
        operator,
        account1,
        cpContractFactoryInstance,
        premiumCalculatorInstance,
        referenceLendingPoolsInstance,
        protectionPoolCycleManagerInstance,
        defaultStateManagerInstance,
        protectionPoolImplementation,
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

    it("run the ProtectionPool test", async () => {
      testProtectionPool(
        deployer,
        operator,
        account1,
        account2,
        account3,
        account4,
        protectionPoolInstance,
        protectionPoolImplementation,
        referenceLendingPoolsInstance,
        protectionPoolCycleManagerInstance,
        defaultStateManagerInstance,
        getProtectionPoolContractFactory
      );
    });

    it("run DefaultStateManager test", async () => {
      testDefaultStateManager(
        deployer,
        account1,
        account3,
        operator,
        defaultStateManagerInstance,
        cpContractFactoryInstance,
        protectionPoolInstance,
        GOLDFINCH_LENDING_POOLS
      );
    });

    // Run this spec last because it moves time forward a lot and that impacts the pool tests
    it("run the ProtectionPoolCycleManager test", async () => {
      testProtectionPoolCycleManager(
        deployer,
        account1,
        protectionPoolCycleManagerInstance,
        cpContractFactoryInstance.address
      );
    });
  });
});
