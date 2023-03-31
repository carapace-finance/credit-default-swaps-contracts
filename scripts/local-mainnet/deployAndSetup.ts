import { formatEther, parseEther } from "@ethersproject/units";
import { BigNumber, Signer } from "ethers";
import { ERC20Upgradeable } from "../../typechain-types/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable";
import { ethers } from "hardhat";

import { ProtectionPurchaseParamsStruct } from "../../typechain-types/contracts/interfaces/IReferenceLendingPools";
import { ProtectionPool } from "../../typechain-types/contracts/core/pool/ProtectionPool";
import { ProtectionPoolCycleManager } from "../../typechain-types/contracts/core/ProtectionPoolCycleManager";

import {
  transferUsdc,
  getUsdcContract,
  parseUSDC
} from "../../test/utils/usdc";
import { impersonateSignerWithEth } from "../../test/utils/utils";
import { moveForwardTime } from "../../test/utils/time";
import {
  payToLendingPoolAddress,
  transferLendingPosition
} from "../../test/utils/goldfinch";
import { deployContracts, DeployContractsResult } from "../../utils/deploy";

import {
  PROTECTION_POOL_CYCLE_PARAMS,
  PROTECTION_POOL_PARAMS,
  PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS,
  GOLDFINCH_LENDING_POOLS,
  LENDING_POOL_PROTOCOLS,
  LENDING_POOL_PURCHASE_LIMIT_IN_DAYS,
  LATE_PAYMENT_GRACE_PERIOD_IN_DAYS
} from "./data";
import { ethers } from "hardhat";

/**
 * This function deploys contracts and setups a playground for testing.
 * This requires a local hardhat node running
 */
export async function deployAndSetup(useMock: boolean) {
  if (useMock) {
    console.log("Starting the setup using mock contracts...");
  } else {
    console.log("Starting the setup...");
  }

  console.log("Deploying contracts...");
  const operator = (await ethers.getSigners())[5];
  const result: DeployContractsResult = await deployContracts(
    PROTECTION_POOL_CYCLE_PARAMS,
    PROTECTION_POOL_PARAMS,
    GOLDFINCH_LENDING_POOLS,
    LENDING_POOL_PROTOCOLS,
    LENDING_POOL_PURCHASE_LIMIT_IN_DAYS,
    LATE_PAYMENT_GRACE_PERIOD_IN_DAYS,
    operator,
    useMock
  );

  if (
    !result.success ||
    !result.deployer ||
    !result.protectionPoolInstance ||
    !result.protectionPoolCycleManagerInstance ||
    (useMock && !result.mockUsdcInstance)
  ) {
    console.error("Deploying contracts failed");
    return;
  }

  const {
    deployer,
    protectionPoolInstance,
    protectionPoolCycleManagerInstance,
    mockUsdcInstance
  } = result;

  const deployerAddress = await deployer.getAddress();
  console.log("Deployed contracts, Deployer address: ", deployerAddress);

  // transfer usdc & lending positions to deployer only when not using mock
  if (!useMock) {
    await transferUsdc(deployerAddress, parseUSDC("100000")); // 100K USDC

    // transfer all lending positions to the deployer
    await transferLendingPositionsToDeployer(deployerAddress);
  }
  // in mock mode, deployer has 100M USDC
  // in non-mock mode, lending position check always passes in mock GoldfinchAdapter, so no need to transfer

  // Setup another user account
  const userAddress = "0x008c84421da5527f462886cec43d2717b686a7e4";
  const user = await impersonateSignerWithEth(userAddress, "10");
  console.log("User address: ", userAddress);

  // transfer usdc to user
  const userUsdcAmount = parseUSDC("101000");
  if (!useMock) {
    await transferUsdc(userAddress, userUsdcAmount); // 101K USDC
  } else {
    await mockUsdcInstance
      .connect(deployer)
      .transfer(userAddress, userUsdcAmount);
  }

  console.log("********** Pool Phase: OpenToSellers **********");
  console.log("********** Pool Cycle: 1, Day: 1     **********");

  // Deposit 1 by user
  await approveAndDeposit(
    protectionPoolInstance,
    parseUSDC("55000"),
    user,
    useMock ? mockUsdcInstance : getUsdcContract(user)
  );

  // Deposit 2 by deployer
  await approveAndDeposit(
    protectionPoolInstance,
    parseUSDC("50000"),
    deployer,
    useMock ? mockUsdcInstance : getUsdcContract(deployer)
  );

  console.log("Pool's details ", await protectionPoolInstance.getPoolDetails());

  console.log("Completed min capital requirement.");

  // move the pool to the next phase
  await protectionPoolInstance.connect(deployer).movePoolPhase();

  console.log("********** Pool Phase: OpenToBuyers **********");

  const lendingPoolAddress = GOLDFINCH_LENDING_POOLS[0];
  const lendingPoolDetails =
    PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS[lendingPoolAddress];

  // buy protection 1
  await transferApproveAndBuyProtection(
    deployer,
    protectionPoolInstance,
    {
      lendingPoolAddress: lendingPoolAddress,
      nftLpTokenId: BigNumber.from(lendingPoolDetails.lendingPosition.tokenId),
      protectionAmount: parseUSDC("150000"),
      protectionDurationInSeconds: (90 * 2 - 5) * 24 * 60 * 60 // PROTECTION_POOL_PARAMS.minProtectionDurationInSeconds
    },
    parseUSDC("35000"),
    useMock ? mockUsdcInstance : getUsdcContract(deployer)
  );

  console.log(
    "Pool's details after buyProtection",
    await protectionPoolInstance.getPoolDetails()
  );
  console.log("block number: ", await ethers.provider.getBlockNumber());

  console.log(
    "Protection Pool leverage ratio: ",
    formatEther(await protectionPoolInstance.calculateLeverageRatio())
  );

  // move the pool to the next phase(Open)
  await protectionPoolInstance.connect(deployer).movePoolPhase();
  console.log(
    "Moved protection pool to new phase: ",
    (await protectionPoolInstance.getPoolInfo()).currentPhase
  );

  console.log("********** Pool Phase: Open **********");

  // Withdrawal request 1: 10K sTokens for deployer
  // We are in cycle with index 0, so withdrawal index is 2
  const withdrawalCycleIndex = 2;
  await requestWithdrawal(
    protectionPoolInstance,
    deployer,
    parseEther("10000"),
    withdrawalCycleIndex
  );

  // Move pool to the next cycle (cycle 2)
  await movePoolCycle(
    protectionPoolInstance,
    protectionPoolCycleManagerInstance
  );

  console.log("********** Pool Cycle: 2, Day: 91     **********");

  // Deposit 3
  await approveAndDeposit(
    protectionPoolInstance,
    parseUSDC("11000"),
    user,
    useMock ? mockUsdcInstance : getUsdcContract(user)
  );

  // Move pool to the next cycle (cycle 3)
  await movePoolCycle(
    protectionPoolInstance,
    protectionPoolCycleManagerInstance
  );

  console.log("block number: ", await ethers.provider.getBlockNumber());

  console.log("********** Pool Cycle: 3, Day: 182     **********");

  if (!useMock) {
    // make payment to all playground lending pools for 3 months, so user can buy protections for them
    for (let i = 0; i < GOLDFINCH_LENDING_POOLS.length; i++) {
      const lendingPoolAddress = GOLDFINCH_LENDING_POOLS[i];
      await payToLendingPoolAddress(
        lendingPoolAddress,
        "900000",
        getUsdcContract(deployer)
      );
      console.log("Payment made to lending pool: ", lendingPoolAddress);
    }
  }

  await protectionPoolInstance.accruePremiumAndExpireProtections(
    GOLDFINCH_LENDING_POOLS
  );
  console.log("Accure premium & expire protetion: ", GOLDFINCH_LENDING_POOLS);

  console.log("Setup completed.");
  console.log("block number: ", await ethers.provider.getBlockNumber());
}

async function movePoolCycle(
  protectionPoolInstance: ProtectionPool,
  poolCycleManagerInstance: ProtectionPoolCycleManager
) {
  // move from open to locked state
  await moveForwardTime(await PROTECTION_POOL_CYCLE_PARAMS.openCycleDuration);

  await poolCycleManagerInstance.calculateAndSetPoolCycleState(
    protectionPoolInstance.address
  );

  // move to new cycle
  const duration = BigNumber.from(
    await PROTECTION_POOL_CYCLE_PARAMS.cycleDuration.toString()
  ).sub(
    BigNumber.from(
      await PROTECTION_POOL_CYCLE_PARAMS.openCycleDuration.toString()
    )
  );
  await moveForwardTime(duration);

  await poolCycleManagerInstance.calculateAndSetPoolCycleState(
    protectionPoolInstance.address
  );
}

async function requestWithdrawal(
  protectionPoolInstance: ProtectionPool,
  user: Signer,
  sTokenAmt: BigNumber,
  withdrawalCycleIndex: number
) {
  await protectionPoolInstance.connect(user).requestWithdrawal(sTokenAmt);

  console.log(
    "User's requested withdrawal Amount: ",
    formatEther(
      await protectionPoolInstance
        .connect(user)
        .getRequestedWithdrawalAmount(withdrawalCycleIndex)
    )
  );
  console.log(
    "Total requested withdrawal amount: ",
    formatEther(
      await protectionPoolInstance.getTotalRequestedWithdrawalAmount(
        withdrawalCycleIndex
      )
    )
  );
}

async function approveAndDeposit(
  protectionPoolInstance: ProtectionPool,
  depositAmt: BigNumber,
  receiver: Signer,
  usdcContract: ERC20Upgradeable
) {
  const receiverAddress = await receiver.getAddress();

  // Approve & deposit
  await usdcContract
    .connect(receiver)
    .approve(protectionPoolInstance.address, depositAmt);

  return await protectionPoolInstance
    .connect(receiver)
    .deposit(depositAmt, receiverAddress);
}

async function transferApproveAndBuyProtection(
  deployer: Signer,
  protectionPoolInstance: ProtectionPool,
  purchaseParams: ProtectionPurchaseParamsStruct,
  maxPremiumAmt: BigNumber,
  usdcContract: ERC20Upgradeable
) {
  // Update purchase params based on lending pool details
  const lendingPoolAddress = await purchaseParams.lendingPoolAddress;
  const lendingPoolDetails =
    PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS[
      lendingPoolAddress.toLowerCase()
    ];
  purchaseParams.nftLpTokenId = lendingPoolDetails.lendingPosition.tokenId;

  console.log(
    "Pool's details before buyProtection",
    await protectionPoolInstance.getPoolDetails()
  );

  // Approve premium USDC from deployer to protection pool
  await usdcContract
    .connect(deployer)
    .approve(protectionPoolInstance.address, maxPremiumAmt);

  console.log("Purchasing a protection using params: ", purchaseParams);

  // Deployer should be able to buy protection
  return await protectionPoolInstance
    .connect(deployer)
    .buyProtection(purchaseParams, maxPremiumAmt);
}

async function transferLendingPositionsToDeployer(deployerAddress: string) {
  console.log("Transferring all lending positions to deployer...");
  const promises = Object.keys(PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS).map(
    async (key: string) => {
      const lendingPoolDetails =
        PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS[key];

      return await transferLendingPosition(
        lendingPoolDetails.lendingPosition.owner,
        deployerAddress,
        lendingPoolDetails.lendingPosition.tokenId
      );
    }
  );

  // wait for all lending position transfers to complete
  await Promise.all(promises);

  console.log("Transferred lending positions to deployer...");
}
