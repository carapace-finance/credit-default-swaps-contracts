import { BigNumber } from "@ethersproject/bignumber";
import { ContractFactory, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { USDC_ADDRESS } from "../test/utils/constants";
import { IPool, Pool } from "../typechain-types/contracts/core/pool/Pool";
import { PoolFactory } from "../typechain-types/contracts/core/PoolFactory";
import { PremiumPricing } from "../typechain-types/contracts/core/PremiumPricing";
import { ReferenceLoans } from "../typechain-types/contracts/core/pool/ReferenceLoans";
import { PoolCycleManager } from "../typechain-types/contracts/core/PoolCycleManager";
import { AccruedPremiumCalculator } from "../typechain-types/contracts/libraries/AccruedPremiumCalculator";

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let poolInstance: Pool;
let poolFactoryInstance: PoolFactory;
let premiumPricingInstance: PremiumPricing;
let referenceLoansInstance: ReferenceLoans;
let poolCycleManagerInstance: PoolCycleManager;
let accruedPremiumCalculatorInstance: AccruedPremiumCalculator;

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
    const AccruedPremiumCalculator = await contractFactory(
      "AccruedPremiumCalculator"
    );
    accruedPremiumCalculatorInstance = await AccruedPremiumCalculator.deploy();
    await accruedPremiumCalculatorInstance.deployed();
    console.log(
      "Deployed AccruedPremiumCalculator to:",
      accruedPremiumCalculatorInstance.address
    );

    const _premiumPricingInstance = await contractFactory("PremiumPricing");
    premiumPricingInstance = await _premiumPricingInstance.deploy(
      "0",
      "0",
      "0"
    );
    await premiumPricingInstance.deployed();
    console.log(
      "PremiumPricing" + " deployed to:",
      premiumPricingInstance.address
    );

    const referenceLoansFactory = await contractFactory("ReferenceLoans");
    referenceLoansInstance = await referenceLoansFactory.deploy();
    await referenceLoansInstance.deployed();
    console.log(
      "ReferenceLoans" + " deployed to:",
      referenceLoansInstance.address
    );

    const _poolCycleManagerFactory = await contractFactory("PoolCycleManager");
    poolCycleManagerInstance = await _poolCycleManagerFactory.deploy();
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

    // Deploy Pool
    const _poolFactory = await contractFactory("Pool", {
      AccruedPremiumCalculator: accruedPremiumCalculatorInstance.address
    });
    const _firstPoolFirstTrancheSalt: string = "0x".concat(
      process.env.FIRST_POOL_FIRST_TRANCHE_SALT
    );

    const _poolCycleParams: IPool.PoolCycleParamsStruct = {
      openCycleDuration: BigNumber.from(10 * 86400), // 10 days
      cycleDuration: BigNumber.from(30 * 86400) // 30 days
    };

    const _poolParams: IPool.PoolParamsStruct = {
      leverageRatioFloor: parseEther("0.1"),
      leverageRatioCeiling: parseEther("0.2"),
      leverageRatioBuffer: parseEther("0.05"),
      minRequiredCapital: parseEther("100000"),
      curvature: parseEther("0.05"),
      poolCycleParams: _poolCycleParams
    };
    const _poolInfo: IPool.PoolInfoStruct = {
      poolId: BigNumber.from(1),
      params: _poolParams,
      underlyingToken: USDC_ADDRESS,
      referenceLoans: referenceLoansInstance.address
    };

    poolInstance = await _poolFactory.deploy(
      _poolInfo,
      premiumPricingInstance.address,
      poolCycleManagerInstance.address,
      "sToken11",
      "sT11"
    );
    await poolInstance.deployed();
    console.log("Pool" + " deployed to:", poolInstance.address);
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
  premiumPricingInstance,
  referenceLoansInstance,
  poolCycleManagerInstance,
  accruedPremiumCalculatorInstance
};
