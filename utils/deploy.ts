import { Contract, ContractFactory, Signer } from "ethers";
import { ethers } from "hardhat";
import { USDC_ADDRESS } from "../test/utils/constants";
import { Tranche } from "../typechain-types/contracts/core/tranche/Tranche";
import { PremiumPricing } from "../typechain-types/contracts/core/PremiumPricing";

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let trancheInstance: Tranche;
let premiumPricingInstance: PremiumPricing;

(async () => {
  [deployer, account1, account2, account3, account4] = await ethers.getSigners();
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
    const _trancheFactory = await contractFactory("Tranche");
    trancheInstance = await _trancheFactory.deploy(
      "lpToken",
      "LPT",
      USDC_ADDRESS,
      USDC_ADDRESS, // need to be changed to the address of the reference loans contract
      USDC_ADDRESS // need to be changed to the address of the premium pricing contract
    );
    await trancheInstance.deployed();
    console.log("Tranche" + " deployed to:", trancheInstance.address);

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
  trancheInstance,
  premiumPricingInstance
};
