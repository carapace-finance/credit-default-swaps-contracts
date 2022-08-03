import { BigNumber } from "@ethersproject/bignumber";
import { ContractFactory, Signer } from "ethers";
import { ethers } from "hardhat";
import { USDC_ADDRESS } from "../test/utils/constants";
import { Pool } from "../typechain-types/contracts/core/pool/Pool";
import { PoolFactory } from "../typechain-types/contracts/core/PoolFactory";
import { PremiumPricing } from "../typechain-types/contracts/core/PremiumPricing";
import { ReferenceLoans } from "../typechain-types/contracts/core/pool/ReferenceLoans";
import { Tranche } from "../typechain-types/contracts/core/tranche/Tranche";
import { TrancheFactory } from "../typechain-types/contracts/core/TrancheFactory";
import { PoolCycleManager } from "../typechain-types/contracts/core/PoolCycleManager";

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let poolInstance: Pool;
let poolFactoryInstance: PoolFactory;
let premiumPricingInstance: PremiumPricing;
let referenceLoansInstance: ReferenceLoans;
let trancheInstance: Tranche;
let trancheFactoryInstance: TrancheFactory;
let poolCycleManagerInstance: PoolCycleManager;

(async () => {
  [deployer, account1, account2, account3, account4] =
    await ethers.getSigners();
})().catch((err) => {
  console.error(err);
});

const contractFactory: Function = async (contractName: string) => {
  const _contractFactory: ContractFactory = await ethers.getContractFactory(
    contractName,
    deployer
  );
  console.log("Deploying " + contractName + "...");
  return _contractFactory;
};

const deployContracts: Function = async () => {
  try {

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

    const _trancheFactory = await contractFactory("Tranche");
    trancheInstance = await _trancheFactory.deploy(
      "sToken",
      "LPT",
      USDC_ADDRESS,
      USDC_ADDRESS, // need to be changed to the address of the reference loans contract
      premiumPricingInstance.address,
      poolCycleManagerInstance.address
    );
    await trancheInstance.deployed();
    console.log("Tranche" + " deployed to:", trancheInstance.address);

    const _trancheFactoryFactory = await contractFactory("TrancheFactory");
    trancheFactoryInstance = await _trancheFactoryFactory.deploy();
    await trancheFactoryInstance.deployed();
    console.log(
      "TrancheFactory" + " deployed to:",
      trancheFactoryInstance.address
    );

    const _poolFactoryFactory = await contractFactory("PoolFactory");
    poolFactoryInstance = await _poolFactoryFactory.deploy();
    await poolFactoryInstance.deployed();
    console.log("PoolFactory" + " deployed to:", poolFactoryInstance.address);

    const _poolFactory = await contractFactory("Pool");
    const _firstPoolFirstTrancheSalt: string = "0x".concat(
      process.env.FIRST_POOL_FIRST_TRANCHE_SALT
    );
    const _firstPoolId: BigNumber = BigNumber.from(1);
    const _floor: BigNumber = BigNumber.from(100);
    const _ceiling: BigNumber = BigNumber.from(500);
    const _name: string = "sToken11";
    const _symbol: string = "sT11";
    poolInstance = await _poolFactory.deploy(
      _firstPoolFirstTrancheSalt,
      _firstPoolId,
      _floor,
      _ceiling,
      USDC_ADDRESS,
      referenceLoansInstance.address,
      premiumPricingInstance.address,
      poolCycleManagerInstance.address,
      _name,
      _symbol
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
  trancheInstance,
  trancheFactoryInstance,
  poolCycleManagerInstance
};
