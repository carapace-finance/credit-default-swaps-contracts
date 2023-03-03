import { ContractFactory, Signer, Contract } from "ethers";
import { ethers, upgrades } from "hardhat";
import { ERC20Upgradeable } from "../typechain-types/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable";
import { USDC_ADDRESS } from "../test/utils/constants";
import { ProtectionPool } from "../typechain-types/contracts/core/pool/ProtectionPool";
import { ProtectionPoolParamsStruct } from "../typechain-types/contracts/interfaces/IProtectionPool";
import { ProtectionPoolCycleParamsStruct } from "../typechain-types/contracts/interfaces/IProtectionPoolCycleManager";
import { ContractFactory as CPContractFactory } from "../typechain-types/contracts/core/ContractFactory";
import { PremiumCalculator } from "../typechain-types/contracts/core/PremiumCalculator";
import { ReferenceLendingPools } from "../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ProtectionPoolCycleManager } from "../typechain-types/contracts/core/ProtectionPoolCycleManager";
import { AccruedPremiumCalculator } from "../typechain-types/contracts/libraries/AccruedPremiumCalculator";
import { RiskFactorCalculator } from "../typechain-types/contracts/libraries/RiskFactorCalculator";
import { GoldfinchAdapter } from "../typechain-types/contracts/adapters/GoldfinchAdapter";
import { DefaultStateManager } from "../typechain-types/contracts/core/DefaultStateManager";
import { MockUsdc } from "../typechain-types/contracts/test/MockUsdc";

export interface DeployContractsResult {
  success: boolean;
  deployer?: Signer | undefined;
  protectionPoolInstance?: ProtectionPool | undefined;
  cpContractFactoryInstance?: CPContractFactory | undefined;
  protectionPoolCycleManagerInstance?: ProtectionPoolCycleManager | undefined;
  defaultStateManagerInstance?: DefaultStateManager | undefined;
  mockUsdcInstance?: ERC20Upgradeable | undefined;
}

let deployer: Signer;
let account1: Signer;
let account2: Signer;
let account3: Signer;
let account4: Signer;

let protectionPoolImplementation: ProtectionPool;
let protectionPoolInstance: ProtectionPool;
let cpContractFactoryInstance: CPContractFactory;
let premiumCalculatorInstance: PremiumCalculator;
let referenceLendingPoolsInstance: ReferenceLendingPools;
let protectionPoolCycleManagerInstance: ProtectionPoolCycleManager;
let accruedPremiumCalculatorInstance: AccruedPremiumCalculator;
let riskFactorCalculatorInstance: RiskFactorCalculator;
let goldfinchAdapterImplementation: GoldfinchAdapter;
let goldfinchAdapterInstance: GoldfinchAdapter;
let referenceLendingPoolsImplementation: ReferenceLendingPools;
let defaultStateManagerInstance: DefaultStateManager;
let protectionPoolHelperInstance: Contract;
let mockUsdcInstance: ERC20Upgradeable;

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

const deployContracts: Function = async (
  _protectionPoolCycleParams: ProtectionPoolCycleParamsStruct,
  _protectionPoolParams: ProtectionPoolParamsStruct,
  _lendingPools: string[],
  _lendingPoolProtocols: number[],
  _lendingPoolPurchaseLimitsInDays: number[],
  _useMock: boolean = false
): Promise<DeployContractsResult> => {
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

    // unsafeAllowLinkedLibraries needs to be set to true for the contract to be deployed
    // More details: https://docs.openzeppelin.com/upgrades-plugins/1.x/faq#why-cant-i-use-external-libraries
    // https://forum.openzeppelin.com/t/upgrade-safe-libraries/13832/2
    premiumCalculatorInstance = (await upgrades.deployProxy(
      premiumCalculatorFactory,
      {
        unsafeAllowLinkedLibraries: true
      }
    )) as PremiumCalculator;

    console.log(
      "PremiumCalculator deployed to: %s at block number %s",
      premiumCalculatorInstance.address,
      await ethers.provider.getBlockNumber()
    );

    // Deploy a proxy to ProtectionPoolCycleManager contract
    const protectionPoolCycleManagerFactory = await contractFactory(
      "ProtectionPoolCycleManager"
    );
    protectionPoolCycleManagerInstance = (await upgrades.deployProxy(
      protectionPoolCycleManagerFactory
    )) as ProtectionPoolCycleManager;
    await protectionPoolCycleManagerInstance.deployed();
    console.log(
      "ProtectionPoolCycleManager is deployed to: %s at block number %s",
      protectionPoolCycleManagerInstance.address,
      await ethers.provider.getBlockNumber()
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
      "DefaultStateManager is deployed to: %s at block number %s",
      defaultStateManagerInstance.address,
      await ethers.provider.getBlockNumber()
    );

    // Deploy ProtectionPoolHelper library contract
    const protectionPoolHelperFactory = await contractFactory(
      "ProtectionPoolHelper",
      {
        AccruedPremiumCalculator: accruedPremiumCalculatorInstance.address
      }
    );
    protectionPoolHelperInstance = await protectionPoolHelperFactory.deploy();
    await protectionPoolHelperInstance.deployed();
    console.log(
      "ProtectionPoolHelper lib is deployed to:",
      protectionPoolHelperInstance.address
    );

    // Deploy a proxy to ContractFactory contract
    const _cpContractFactoryFactory = await contractFactory("ContractFactory");
    cpContractFactoryInstance = (await upgrades.deployProxy(
      _cpContractFactoryFactory,
      [
        protectionPoolCycleManagerInstance.address,
        defaultStateManagerInstance.address
      ]
    )) as CPContractFactory;
    await cpContractFactoryInstance.deployed();
    console.log(
      "ContractFactory is deployed to: %s at block number %s",
      cpContractFactoryInstance.address,
      await ethers.provider.getBlockNumber()
    );

    /// Sets pool factory address into the ProtectionPoolCycleManager & DefaultStateManager
    /// This is required to enable the ProtectionPoolCycleManager & DefaultStateManager to register a new pool when it is created
    /// "setPoolFactory" must be called by the owner
    await protectionPoolCycleManagerInstance
      .connect(deployer)
      .setContractFactory(cpContractFactoryInstance.address);
    await defaultStateManagerInstance
      .connect(deployer)
      .setContractFactory(cpContractFactoryInstance.address);

    // Deploy MockGoldfinchAdapter implementation contract
    if (_useMock) {
      const mockGoldfinchAdapterFactory = await contractFactory(
        "MockGoldfinchAdapter"
      );
      goldfinchAdapterImplementation =
        await mockGoldfinchAdapterFactory.deploy();
      await goldfinchAdapterImplementation.deployed();
      console.log(
        "MockGoldfinchAdapter implementation is deployed to:",
        goldfinchAdapterImplementation.address
      );
    } else {
      // Deploy GoldfinchAdapter implementation contract
      const goldfinchAdapterFactory = await contractFactory("GoldfinchAdapter");
      goldfinchAdapterImplementation = await goldfinchAdapterFactory.deploy();
      await goldfinchAdapterImplementation.deployed();
      console.log(
        "GoldfinchAdapter implementation is deployed to:",
        goldfinchAdapterImplementation.address
      );
    }

    // Create an upgradable instance of GoldfinchAdapter
    await cpContractFactoryInstance.createLendingProtocolAdapter(
      0, // Goldfinch
      goldfinchAdapterImplementation.address,
      goldfinchAdapterImplementation.interface.encodeFunctionData(
        "initialize",
        [await deployer.getAddress()]
      )
    );

    // Retrieve an instance of GoldfinchAdapter from the LendingProtocolAdapterFactory
    goldfinchAdapterInstance = (await ethers.getContractAt(
      _useMock ? "MockGoldfinchAdapter" : "GoldfinchAdapter",
      await cpContractFactoryInstance.getLendingProtocolAdapter(0)
    )) as GoldfinchAdapter;

    console.log(
      "GoldfinchAdapter is deployed at: %s at block number %s",
      goldfinchAdapterInstance.address,
      await ethers.provider.getBlockNumber()
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

    // Create an instance of the ReferenceLendingPools
    await cpContractFactoryInstance.createReferenceLendingPools(
      referenceLendingPoolsImplementation.address,
      _lendingPools,
      _lendingPoolProtocols,
      _lendingPoolPurchaseLimitsInDays,
      cpContractFactoryInstance.address
    );
    referenceLendingPoolsInstance =
      await getLatestReferenceLendingPoolsInstance(cpContractFactoryInstance);

    // Deploy a ProtectionPool implementation contract
    const protectionPoolFactory = await getProtectionPoolContractFactory();
    protectionPoolImplementation = await protectionPoolFactory.deploy();
    await protectionPoolImplementation.deployed();
    console.log(
      "ProtectionPool implementation is deployed to: %s at block number %s",
      protectionPoolImplementation.address,
      await ethers.provider.getBlockNumber()
    );

    if (_useMock) {
      /// deploy mock USDC contract
      const mockUSDCFactory = await contractFactory("MockUsdc");
      mockUsdcInstance = (await upgrades.deployProxy(mockUSDCFactory, [
        await deployer.getAddress()
      ])) as MockUsdc;
      await mockUsdcInstance.deployed();
      console.log(
        "MockUsdc is deployed to: %s at block number %s",
        mockUsdcInstance.address,
        await ethers.provider.getBlockNumber()
      );

      console.log(
        "Balance of deployer: %s",
        await mockUsdcInstance.balanceOf(await deployer.getAddress())
      );
    }

    // Create an instance of the ProtectionPool, which should be upgradable
    // Create a pool using PoolFactory instead of deploying new pool directly to mimic the prod behavior
    await cpContractFactoryInstance.createProtectionPool(
      protectionPoolImplementation.address,
      _protectionPoolParams,
      _protectionPoolCycleParams,
      _useMock ? mockUsdcInstance.address : USDC_ADDRESS,
      referenceLendingPoolsInstance.address,
      premiumCalculatorInstance.address,
      "sToken11",
      "sT11"
    );

    protectionPoolInstance = await getLatestProtectionPoolInstance(
      cpContractFactoryInstance
    );

    return {
      success: true,
      deployer,
      protectionPoolInstance,
      protectionPoolCycleManagerInstance,
      defaultStateManagerInstance,
      cpContractFactoryInstance,
      mockUsdcInstance
    };
  } catch (e) {
    console.log(e);
    return { success: false };
  }
};

async function getLatestReferenceLendingPoolsInstance(
  cpContractFactory: CPContractFactory
): Promise<ReferenceLendingPools> {
  const referenceLendingPoolsList =
    await cpContractFactory.getReferenceLendingPoolsList();
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

async function getLatestProtectionPoolInstance(
  contractFactoryInstance: CPContractFactory
): Promise<ProtectionPool> {
  const pools = await contractFactoryInstance.getProtectionPools();
  const newPoolInstance = (await ethers.getContractAt(
    "ProtectionPool",
    pools[pools.length - 1]
  )) as ProtectionPool;

  console.log(
    "Latest ProtectionPool instance is deployed at: %s at block number %s",
    newPoolInstance.address,
    await ethers.provider.getBlockNumber()
  );
  return newPoolInstance;
}

async function getProtectionPoolContractFactory(
  contractName = "ProtectionPool"
) {
  return await contractFactory(contractName, {
    AccruedPremiumCalculator: accruedPremiumCalculatorInstance.address,
    ProtectionPoolHelper: protectionPoolHelperInstance.address
  });
}

export {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  protectionPoolImplementation,
  protectionPoolInstance,
  cpContractFactoryInstance,
  premiumCalculatorInstance,
  referenceLendingPoolsInstance, // This is the proxy instance cloned from implementation
  protectionPoolCycleManagerInstance,
  accruedPremiumCalculatorInstance,
  riskFactorCalculatorInstance,
  goldfinchAdapterImplementation,
  goldfinchAdapterInstance,
  referenceLendingPoolsImplementation, // implementation contract which is used to create proxy contract
  defaultStateManagerInstance,
  getLatestReferenceLendingPoolsInstance,
  getLatestProtectionPoolInstance,
  getProtectionPoolContractFactory
};
