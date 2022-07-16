import { Contract, ContractFactory, Signer } from "ethers";
import { ethers } from "hardhat";
import { USDC_ADDRESS } from "../test/utils/constants";
import { Tranche } from "../typechain-types/contracts/core/tranche/Tranche";
import { PoolFactory } from "../typechain-types/contracts/core/PoolFactory";
import { PremiumPricing } from "../typechain-types/contracts/core/PremiumPricing";

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let trancheInstance: Tranche;
let poolFactoryInstance: PoolFactory;
let premiumPricingInstance: PremiumPricing;

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

    const _trancheFactory = await contractFactory("Tranche");
    trancheInstance = await _trancheFactory.deploy(
      "sToken",
      "LPT",
      USDC_ADDRESS,
      USDC_ADDRESS, // need to be changed to the address of the reference loans contract
      premiumPricingInstance.address
    );
    await trancheInstance.deployed();
    console.log("Tranche" + " deployed to:", trancheInstance.address);

    const _poolFactoryFactory = await contractFactory("PoolFactory");
    poolFactoryInstance = await _poolFactoryFactory.deploy();
    await poolFactoryInstance.deployed();
    console.log("PoolFactory" + " deployed to:", poolFactoryInstance.address);
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
  poolFactoryInstance,
  trancheInstance,
  premiumPricingInstance
};
