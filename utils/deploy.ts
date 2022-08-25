import { BigNumber } from "@ethersproject/bignumber";
import { ContractFactory, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { USDC_ADDRESS } from "../test/utils/constants";
import { IPool, Pool } from "../typechain-types/contracts/core/pool/Pool";
import { PoolFactory } from "../typechain-types/contracts/core/PoolFactory";
import { RiskPremiumCalculator } from "../typechain-types/contracts/core/RiskPremiumCalculator";
import { ReferenceLendingPools } from "../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { PoolCycleManager } from "../typechain-types/contracts/core/PoolCycleManager";
import { AccruedPremiumCalculator } from "../typechain-types/contracts/libraries/AccruedPremiumCalculator";
import { RiskFactorCalculator } from "../typechain-types/contracts/libraries/RiskFactorCalculator";
import { parseUSDC } from "../test/utils/usdc";

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let poolInstance: Pool;
let poolFactoryInstance: PoolFactory;
let riskPremiumCalculatorInstance: RiskPremiumCalculator;
let referenceLendingPoolsInstance: ReferenceLendingPools;
let poolCycleManagerInstance: PoolCycleManager;
let accruedPremiumCalculatorInstance: AccruedPremiumCalculator;
let riskFactorCalculatorInstance: RiskFactorCalculator;

(async () => {
  [deployer, account1, account2, account3, account4] =
    await ethers.getSigners();
})().catch((err) => {
  console.error(err);
});

const contractFactory: Function = async (
  contractName: string,
  libraries: any
) => {
  const _contractFactory: ContractFactory = await ethers.getContractFactory(
    contractName,
    { signer: deployer, libraries }
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

    const riskPremiumCalculatorFactory = await contractFactory(
      "RiskPremiumCalculator",
      riskFactorLibRef
    );
    riskPremiumCalculatorInstance = await riskPremiumCalculatorFactory.deploy();
    await riskPremiumCalculatorInstance.deployed();
    console.log(
      "RiskPremiumCalculator deployed to:",
      riskPremiumCalculatorInstance.address
    );

    const referenceLendingPoolsFactory = await contractFactory(
      "ReferenceLendingPools"
    );
    referenceLendingPoolsInstance = await referenceLendingPoolsFactory.deploy();
    await referenceLendingPoolsInstance.deployed();
    console.log(
      "ReferenceLendingPools" + " deployed to:",
      referenceLendingPoolsInstance.address
    );

    const poolCycleManagerFactory = await contractFactory("PoolCycleManager");
    poolCycleManagerInstance = await poolCycleManagerFactory.deploy();
    await poolCycleManagerInstance.deployed();
    console.log(
      "PoolCycleManager" + " deployed to:",
      poolCycleManagerInstance.address
    );

    // Deploy PoolFactory
    const _poolFactoryFactory = await contractFactory("PoolFactory", {
      AccruedPremiumCalculator: accruedPremiumCalculatorInstance.address
    });
    poolFactoryInstance = await _poolFactoryFactory.deploy();
    await poolFactoryInstance.deployed();
    console.log("PoolFactory" + " deployed to:", poolFactoryInstance.address);

    const _poolCycleParams: IPool.PoolCycleParamsStruct = {
      openCycleDuration: BigNumber.from(10 * 86400), // 10 days
      cycleDuration: BigNumber.from(30 * 86400) // 30 days
    };

    const _poolParams: IPool.PoolParamsStruct = {
      leverageRatioFloor: parseEther("0.1"),
      leverageRatioCeiling: parseEther("0.2"),
      leverageRatioBuffer: parseEther("0.05"),
      minRequiredCapital: parseUSDC("50000"),
      minRequiredProtection: parseUSDC("100000"),
      curvature: parseEther("0.05"),
      minRiskPremiumPercent: parseEther("0.2"),
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
      riskPremiumCalculatorInstance.address,
      "sToken11",
      "sT11"
    );

    const receipt: any = await tx.wait();
    poolInstance = (await ethers.getContractAt(
      "Pool",
      receipt.events[4].args.poolAddress
    )) as Pool;
    console.log("Pool created at: ", poolInstance.address);
  } catch (e) {
    console.log(e);
  }
};

export {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolInstance,
  poolFactoryInstance,
  riskPremiumCalculatorInstance as premiumPricingInstance,
  referenceLendingPoolsInstance,
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance
};
