import { BigNumber } from "@ethersproject/bignumber";
import { ContractFactory, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { USDC_ADDRESS } from "../test/utils/constants";
import { IPool, Pool } from "../typechain-types/contracts/core/pool/Pool";
import { PoolFactory } from "../typechain-types/contracts/core/PoolFactory";
import { PremiumCalculator } from "../typechain-types/contracts/core/PremiumCalculator";
import { ReferenceLendingPools } from "../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { PoolCycleManager } from "../typechain-types/contracts/core/PoolCycleManager";
import { AccruedPremiumCalculator } from "../typechain-types/contracts/libraries/AccruedPremiumCalculator";
import { RiskFactorCalculator } from "../typechain-types/contracts/libraries/RiskFactorCalculator";
import { GoldfinchV2Adapter } from "../typechain-types/contracts/adapters/GoldfinchV2Adapter";
import { ReferenceLendingPoolsFactory } from "../typechain-types/contracts/core/ReferenceLendingPoolsFactory";
import { DefaultStateManager } from "../typechain-types/contracts/core/DefaultStateManager";

import { parseUSDC } from "../test/utils/usdc";

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let poolInstance: Pool;
let poolFactoryInstance: PoolFactory;
let premiumCalculatorInstance: PremiumCalculator;
let referenceLendingPoolsInstance: ReferenceLendingPools;
let poolCycleManagerInstance: PoolCycleManager;
let accruedPremiumCalculatorInstance: AccruedPremiumCalculator;
let riskFactorCalculatorInstance: RiskFactorCalculator;
let goldfinchV2AdapterInstance: GoldfinchV2Adapter;
let referenceLendingPoolsFactoryInstance: ReferenceLendingPoolsFactory;
let referenceLendingPoolsImplementation: ReferenceLendingPools;
let defaultStateManagerInstance: DefaultStateManager;

const GOLDFINCH_LENDING_POOLS = [
  "0xb26b42dd5771689d0a7faeea32825ff9710b9c11",
  "0xd09a57127bc40d680be7cb061c2a6629fe71abef"
];

(async () => {
  [deployer, account1, account2, account3, account4] =
    await ethers.getSigners();
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
    const riskFactorCalculatorFactory = await contractFactory(
      "RiskFactorCalculator"
    );
    riskFactorCalculatorInstance = await riskFactorCalculatorFactory.deploy();
    await riskFactorCalculatorInstance.deployed();
    console.log(
      "RiskFactorCalculator deployed to:",
      riskFactorCalculatorInstance.address
    );

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
      "ReferenceLendingPools",
      {},
      account1
    );
    referenceLendingPoolsImplementation =
      await referenceLendingPoolsFactory.deploy();
    await referenceLendingPoolsImplementation.deployed();
    console.log(
      "ReferenceLendingPools Implementation" + " deployed to:",
      referenceLendingPoolsImplementation.address
    );

    const referenceLendingPoolsFactoryFactory = await contractFactory(
      "ReferenceLendingPoolsFactory"
    );
    referenceLendingPoolsFactoryInstance =
      await referenceLendingPoolsFactoryFactory.deploy(
        referenceLendingPoolsImplementation.address
      );
    await referenceLendingPoolsFactoryInstance.deployed();
    console.log(
      "ReferenceLendingPoolsFactory" + " deployed to:",
      referenceLendingPoolsFactoryInstance.address
    );

    // Create an instance of the ReferenceLendingPools
    const _lendingProtocols = [0, 0]; // 0 = Goldfinch
    const _purchaseLimitsInDays = [90, 25];
    const tx1 =
      await referenceLendingPoolsFactoryInstance.createReferenceLendingPools(
        GOLDFINCH_LENDING_POOLS,
        _lendingProtocols,
        _purchaseLimitsInDays
      );
    referenceLendingPoolsInstance =
      await getReferenceLendingPoolsInstanceFromTx(tx1);

    // Deploy PoolCycleManager
    const poolCycleManagerFactory = await contractFactory("PoolCycleManager");
    poolCycleManagerInstance = await poolCycleManagerFactory.deploy();
    await poolCycleManagerInstance.deployed();
    console.log(
      "PoolCycleManager" + " deployed to:",
      poolCycleManagerInstance.address
    );

    // Deploy GoldfinchV2Adapter
    const goldfinchV2AdapterFactory = await contractFactory(
      "GoldfinchV2Adapter"
    );
    goldfinchV2AdapterInstance = await goldfinchV2AdapterFactory.deploy();
    await goldfinchV2AdapterInstance.deployed();
    console.log(
      "GoldfinchV2Adapter" + " deployed to:",
      goldfinchV2AdapterInstance.address
    );

    // Deploy PoolFactory
    const _poolFactoryFactory = await contractFactory("PoolFactory", {
      AccruedPremiumCalculator: accruedPremiumCalculatorInstance.address
    });
    poolFactoryInstance = await _poolFactoryFactory.deploy();
    await poolFactoryInstance.deployed();
    console.log("PoolFactory" + " deployed to:", poolFactoryInstance.address);

    // Get DefaultStateManager instance from pool factory
    defaultStateManagerInstance = (await ethers.getContractAt(
      "DefaultStateManager",
      await poolFactoryInstance.getDefaultStateManager()
    )) as DefaultStateManager;
    console.log(
      "DefaultStateManager" + " is deployed at:",
      defaultStateManagerInstance.address
    );

    const _poolCycleParams: IPool.PoolCycleParamsStruct = {
      openCycleDuration: BigNumber.from(10 * 86400), // 10 days
      cycleDuration: BigNumber.from(30 * 86400) // 30 days
    };

    const _poolParams: IPool.PoolParamsStruct = {
      leverageRatioFloor: parseEther("0.1"),
      leverageRatioCeiling: parseEther("0.2"),
      leverageRatioBuffer: parseEther("0.05"),
      minRequiredCapital: parseUSDC("50000"),
      minRequiredProtection: parseUSDC("200000"),
      curvature: parseEther("0.05"),
      minCarapaceRiskPremiumPercent: parseEther("0.02"),
      underlyingRiskPremiumPercent: parseEther("0.1"),
      poolCycleParams: _poolCycleParams
    };

    // Create a pool using PoolFactory instead of deploying new pool directly to mimic the prod behavior
    const _firstPoolFirstTrancheSalt: string = "0x".concat(
      process.env.FIRST_POOL_SALT
    );

    const tx = await poolFactoryInstance.createPool(
      _firstPoolFirstTrancheSalt,
      _poolParams,
      USDC_ADDRESS,
      referenceLendingPoolsInstance.address,
      premiumCalculatorInstance.address,
      "sToken11",
      "sT11"
    );
    poolInstance = await getPoolInstanceFromTx(tx);
  } catch (e) {
    console.log(e);
  }
};

async function getReferenceLendingPoolsInstanceFromTx(
  tx: any
): Promise<ReferenceLendingPools> {
  const receipt: any = await tx.wait();

  const referenceLendingPoolsCreatedEvent = receipt.events.find(
    (eventInfo: any) => eventInfo.event === "ReferenceLendingPoolsCreated"
  );

  const newReferenceLendingPoolsInstance = (await ethers.getContractAt(
    "ReferenceLendingPools",
    referenceLendingPoolsCreatedEvent.args.referenceLendingPools
  )) as ReferenceLendingPools;

  console.log(
    "ReferenceLendingPools instance created at: ",
    newReferenceLendingPoolsInstance.address
  );

  return newReferenceLendingPoolsInstance;
}

async function getPoolInstanceFromTx(tx: any): Promise<Pool> {
  const receipt: any = await tx.wait();

  const poolCreatedEvent = receipt.events.find(
    (eventInfo: any) => eventInfo.event === "PoolCreated"
  );

  const newPoolInstance = (await ethers.getContractAt(
    "Pool",
    poolCreatedEvent.args.poolAddress
  )) as Pool;

  console.log("Pool instance created at: ", newPoolInstance.address);

  return newPoolInstance;
}

export {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolInstance,
  poolFactoryInstance,
  premiumCalculatorInstance,
  referenceLendingPoolsInstance, // This is the proxy instance cloned from implementation
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance,
  riskFactorCalculatorInstance,
  goldfinchV2AdapterInstance,
  referenceLendingPoolsImplementation, // implementation contract which is used to create proxy contract
  referenceLendingPoolsFactoryInstance,
  defaultStateManagerInstance,
  GOLDFINCH_LENDING_POOLS,
  getReferenceLendingPoolsInstanceFromTx,
  getPoolInstanceFromTx
};
