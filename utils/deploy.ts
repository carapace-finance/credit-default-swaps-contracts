import { ContractFactory, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers, upgrades } from "hardhat";
import { USDC_ADDRESS } from "../test/utils/constants";
import { Pool } from "../typechain-types/contracts/core/pool/Pool";
import {
  PoolParamsStruct,
  PoolCycleParamsStruct
} from "../typechain-types/contracts/interfaces/IPool";
import { PoolFactory } from "../typechain-types/contracts/core/PoolFactory";
import { PremiumCalculator } from "../typechain-types/contracts/core/PremiumCalculator";
import { ReferenceLendingPools } from "../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { PoolCycleManager } from "../typechain-types/contracts/core/PoolCycleManager";
import { AccruedPremiumCalculator } from "../typechain-types/contracts/libraries/AccruedPremiumCalculator";
import { RiskFactorCalculator } from "../typechain-types/contracts/libraries/RiskFactorCalculator";
import { GoldfinchAdapter } from "../typechain-types/contracts/adapters/GoldfinchAdapter";
import { ReferenceLendingPoolsFactory } from "../typechain-types/contracts/core/ReferenceLendingPoolsFactory";
import { DefaultStateManager } from "../typechain-types/contracts/core/DefaultStateManager";
import { LendingProtocolAdapterFactory } from "../typechain-types/contracts/core/LendingProtocolAdapterFactory";

import { parseUSDC } from "../test/utils/usdc";
import { getDaysInSeconds } from "../test/utils/time";

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let poolImplementation: Pool;
let poolInstance: Pool;
let poolFactoryInstance: PoolFactory;
let premiumCalculatorInstance: PremiumCalculator;
let referenceLendingPoolsInstance: ReferenceLendingPools;
let poolCycleManagerInstance: PoolCycleManager;
let accruedPremiumCalculatorInstance: AccruedPremiumCalculator;
let riskFactorCalculatorInstance: RiskFactorCalculator;
let goldfinchAdapterInstance: GoldfinchAdapter;
let referenceLendingPoolsFactoryInstance: ReferenceLendingPoolsFactory;
let referenceLendingPoolsImplementation: ReferenceLendingPools;
let defaultStateManagerInstance: DefaultStateManager;
let lendingProtocolAdapterFactoryInstance: LendingProtocolAdapterFactory;

const GOLDFINCH_LENDING_POOLS = [
  "0xb26b42dd5771689d0a7faeea32825ff9710b9c11",
  "0xd09a57127bc40d680be7cb061c2a6629fe71abef"
];

(async () => {
  [deployer, account1, account2, account3, account4] =
    await ethers.getSigners();
  console.log("Deployer address: ", await deployer.getAddress());
})().catch((err) => {
  console.error(err);
});

const contractFactory: Function = async (
  contractName: string,
  libraries: any,
  deployerAccount: Signer = deployer
) => {
  const _contractFactory: ContractFactory = await ethers.getContractFactory(
    contractName,
    { signer: deployerAccount, libraries }
  );
  console.log("Deploying " + contractName + "...");
  return _contractFactory;
};

const deployContracts: Function = async () => {
  try {
    // Deploy RiskFactorCalculator library
    const riskFactorCalculatorFactory = await contractFactory(
      "RiskFactorCalculator"
    );
    riskFactorCalculatorInstance = await riskFactorCalculatorFactory.deploy();
    await riskFactorCalculatorInstance.deployed();
    console.log(
      "RiskFactorCalculator deployed to:",
      riskFactorCalculatorInstance.address
    );

    // Deploy AccruedPremiumCalculator library
    const riskFactorLibRef = {
      RiskFactorCalculator: riskFactorCalculatorInstance.address
    };
    const AccruedPremiumCalculator = await contractFactory(
      "AccruedPremiumCalculator",
      riskFactorLibRef
    );
    accruedPremiumCalculatorInstance = await AccruedPremiumCalculator.deploy();
    await accruedPremiumCalculatorInstance.deployed();
    console.log(
      "AccruedPremiumCalculator deployed to:",
      accruedPremiumCalculatorInstance.address
    );

    // Deploy PremiumCalculator contract
    const premiumCalculatorFactory = await contractFactory(
      "PremiumCalculator",
      riskFactorLibRef
    );
    premiumCalculatorInstance = await premiumCalculatorFactory.deploy();
    await premiumCalculatorInstance.deployed();
    console.log(
      "PremiumCalculator deployed to:",
      premiumCalculatorInstance.address
    );

    // Deploy ReferenceLendingPools Implementation contract
    const referenceLendingPoolsFactory = await contractFactory(
      "ReferenceLendingPools"
    );
    referenceLendingPoolsImplementation =
      await referenceLendingPoolsFactory.deploy();
    await referenceLendingPoolsImplementation.deployed();
    console.log(
      "ReferenceLendingPools Implementation deployed to:",
      referenceLendingPoolsImplementation.address
    );

    // Deploy a proxy to LendingProtocolAdapterFactory contract
    const lendingProtocolAdapterFactory = await contractFactory(
      "LendingProtocolAdapterFactory"
    );
    lendingProtocolAdapterFactoryInstance = (await upgrades.deployProxy(
      lendingProtocolAdapterFactory
    )) as LendingProtocolAdapterFactory;
    await lendingProtocolAdapterFactoryInstance.deployed();
    console.log(
      "LendingProtocolAdapterFactory deployed to: ",
      lendingProtocolAdapterFactoryInstance.address
    );

    // Deploy a proxy to ReferenceLendingPoolsFactory contract to make it upgradeable
    const referenceLendingPoolsFactoryFactory = await contractFactory(
      "ReferenceLendingPoolsFactory"
    );
    referenceLendingPoolsFactoryInstance = (await upgrades.deployProxy(
      referenceLendingPoolsFactoryFactory
    )) as ReferenceLendingPoolsFactory;
    await referenceLendingPoolsFactoryInstance.deployed();
    console.log(
      "ReferenceLendingPoolsFactory deployed to:",
      referenceLendingPoolsFactoryInstance.address
    );

    // Create an instance of the ReferenceLendingPools
    const _lendingProtocols = [0, 0]; // 0 = Goldfinch
    const _purchaseLimitsInDays = [90, 60];
    await referenceLendingPoolsFactoryInstance.createReferenceLendingPools(
      referenceLendingPoolsImplementation.address,
      GOLDFINCH_LENDING_POOLS,
      _lendingProtocols,
      _purchaseLimitsInDays,
      lendingProtocolAdapterFactoryInstance.address
    );
    referenceLendingPoolsInstance =
      await getLatestReferenceLendingPoolsInstance(
        referenceLendingPoolsFactoryInstance
      );

    // Retrieve an instance of GoldfinchAdapter from the LendingProtocolAdapterFactory
    goldfinchAdapterInstance = (await ethers.getContractAt(
      "GoldfinchAdapter",
      await lendingProtocolAdapterFactoryInstance.getLendingProtocolAdapter(0)
    )) as GoldfinchAdapter;

    console.log(
      "GoldfinchAdapter is deployed to: ",
      goldfinchAdapterInstance.address
    );

    // Deploy a proxy to PoolCycleManager contract
    const poolCycleManagerFactory = await contractFactory("PoolCycleManager");
    poolCycleManagerInstance = (await upgrades.deployProxy(
      poolCycleManagerFactory
    )) as PoolCycleManager;
    await poolCycleManagerInstance.deployed();
    console.log(
      "PoolCycleManager is deployed to: ",
      poolCycleManagerInstance.address
    );

    // Deploy a proxy to DefaultStateManager contract
    const defaultStateManagerFactory = await contractFactory(
      "DefaultStateManager"
    );
    defaultStateManagerInstance = (await upgrades.deployProxy(
      defaultStateManagerFactory
    )) as DefaultStateManager;
    await defaultStateManagerInstance.deployed();
    console.log(
      "DefaultStateManager is deployed to: ",
      defaultStateManagerInstance.address
    );

    // Deploy PoolHelper library contract
    const poolHelperFactory = await contractFactory("PoolHelper", {
      AccruedPremiumCalculator: accruedPremiumCalculatorInstance.address
    });
    const poolHelperInstance = await poolHelperFactory.deploy();
    await poolHelperInstance.deployed();
    console.log("PoolHelper lib is deployed to:", poolHelperInstance.address);

    // Deploy a proxy to PoolFactory contract
    const _poolFactoryFactory = await contractFactory("PoolFactory");
    poolFactoryInstance = (await upgrades.deployProxy(_poolFactoryFactory, [
      poolCycleManagerInstance.address,
      defaultStateManagerInstance.address
    ])) as PoolFactory;
    await poolFactoryInstance.deployed();
    console.log("PoolFactory is deployed to: ", poolFactoryInstance.address);

    /// Sets pool factory address into the PoolCycleManager & DefaultStateManager
    /// This is required to enable the PoolCycleManager & DefaultStateManager to register a new pool when it is created
    /// "setPoolFactory" must be called by the owner
    await poolCycleManagerInstance
      .connect(deployer)
      .setPoolFactory(poolFactoryInstance.address);
    await defaultStateManagerInstance
      .connect(deployer)
      .setPoolFactory(poolFactoryInstance.address);

    // Deploy a Pool implementation contract
    const poolFactory = await contractFactory("Pool", {
      AccruedPremiumCalculator: accruedPremiumCalculatorInstance.address,
      PoolHelper: poolHelperInstance.address
    });
    poolImplementation = await poolFactory.deploy();
    await poolImplementation.deployed();
    console.log(
      "Pool implementation is deployed to: ",
      poolImplementation.address
    );

    /// Create an instance of the Pool, which should be upgradable
    // Create a pool using PoolFactory instead of deploying new pool directly to mimic the prod behavior
    const _poolCycleParams: PoolCycleParamsStruct = {
      openCycleDuration: getDaysInSeconds(10),
      cycleDuration: getDaysInSeconds(30)
    };

    const _poolParams: PoolParamsStruct = {
      leverageRatioFloor: parseEther("0.5"),
      leverageRatioCeiling: parseEther("1"),
      leverageRatioBuffer: parseEther("0.05"),
      minRequiredCapital: parseUSDC("100000"), // 100k
      curvature: parseEther("0.05"),
      minCarapaceRiskPremiumPercent: parseEther("0.02"),
      underlyingRiskPremiumPercent: parseEther("0.1"),
      minProtectionDurationInSeconds: getDaysInSeconds(10),
      poolCycleParams: _poolCycleParams,
      protectionExtensionGracePeriodInSeconds: getDaysInSeconds(14) // 2 weeks
    };

    await poolFactoryInstance.createPool(
      poolImplementation.address,
      _poolParams,
      USDC_ADDRESS,
      referenceLendingPoolsInstance.address,
      premiumCalculatorInstance.address,
      "sToken11",
      "sT11"
    );

    poolInstance = await getLatestPoolInstance(poolFactoryInstance);
  } catch (e) {
    console.log(e);
  }
};

async function getLatestReferenceLendingPoolsInstance(
  referenceLendingPoolsFactoryInstance: ReferenceLendingPoolsFactory
): Promise<ReferenceLendingPools> {
  const referenceLendingPoolsList =
    await referenceLendingPoolsFactoryInstance.getReferenceLendingPoolsList();
  const newReferenceLendingPoolsInstance = (await ethers.getContractAt(
    "ReferenceLendingPools",
    referenceLendingPoolsList[referenceLendingPoolsList.length - 1]
  )) as ReferenceLendingPools;

  console.log(
    "ReferenceLendingPools instance created at: ",
    newReferenceLendingPoolsInstance.address
  );

  return newReferenceLendingPoolsInstance;
}

async function getLatestPoolInstance(
  poolFactoryInstance: PoolFactory
): Promise<Pool> {
  const pools = await poolFactoryInstance.getPools();
  const newPoolInstance = (await ethers.getContractAt(
    "Pool",
    pools[pools.length - 1]
  )) as Pool;

  console.log("Latest pool instance is deployed at: ", newPoolInstance.address);
  return newPoolInstance;
}

export {
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
  referenceLendingPoolsInstance, // This is the proxy instance cloned from implementation
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance,
  riskFactorCalculatorInstance,
  goldfinchAdapterInstance,
  lendingProtocolAdapterFactoryInstance,
  referenceLendingPoolsImplementation, // implementation contract which is used to create proxy contract
  referenceLendingPoolsFactoryInstance,
  defaultStateManagerInstance,
  GOLDFINCH_LENDING_POOLS,
  getLatestReferenceLendingPoolsInstance,
  getLatestPoolInstance
};
