import { formatEther, parseEther } from "@ethersproject/units";
import {
  transferUsdc,
  getUsdcContract,
  parseUSDC
} from "../../test/utils/usdc";
import { ProtectionPurchaseParamsStruct } from "../../typechain-types/contracts/interfaces/IReferenceLendingPools";

import { impersonateSignerWithEth } from "../../test/utils/utils";
import { ProtectionPool } from "../../typechain-types/contracts/core/pool/ProtectionPool";
import { BigNumber, Signer } from "ethers";
import { moveForwardTime } from "../../test/utils/time";
import { ProtectionPoolCycleManager } from "../../typechain-types/contracts/core/ProtectionPoolCycleManager";
import { payToLendingPoolAddress } from "../../test/utils/goldfinch";

import {
  deployer,
  deployContracts,
  protectionPoolInstance,
  protectionPoolCycleManagerInstance
} from "../../utils/deploy";

import {
  PROTECTION_POOL_CYCLE_PARAMS,
  PROTECTION_POOL_PARAMS,
  PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS,
  GOLDFINCH_LENDING_POOLS,
  LENDING_POOL_PROTOCOLS,
  LENDING_POOL_PURCHASE_LIMIT_IN_DAYS
} from "./data";

/**
 * This function deploys contracts and setups a playground for testing.
 * This requires a local hardhat node running.
 */
async function deployAndSetup() {
  console.log("Starting the setup...");

  console.log("Deploying contracts...");
  const result = await deployContracts(
    PROTECTION_POOL_CYCLE_PARAMS,
    PROTECTION_POOL_PARAMS,
    GOLDFINCH_LENDING_POOLS,
    LENDING_POOL_PROTOCOLS,
    LENDING_POOL_PURCHASE_LIMIT_IN_DAYS
  );
  if (!result) {
    console.error("Deploying contracts failed");
    return;
  }

  const deployerAddress = await deployer.getAddress();
  console.log("Deployed contracts, Deployer address: ", deployerAddress);

  // transfer usdc to deployer
  await transferUsdc(deployerAddress, parseUSDC("100000")); // 100K USDC

  // Setup another user account
  const userAddress = "0x008c84421da5527f462886cec43d2717b686a7e4";
  const user = await impersonateSignerWithEth(userAddress, "10");
  console.log("User address: ", userAddress);

  // transfer usdc to user
  await transferUsdc(userAddress, parseUSDC("101000")); // 101K USDC

  console.log("********** Pool Phase: OpenToSellers **********");
  console.log("********** Pool Cycle: 1, Day: 1     **********");

  // Deposit 1 by user
  await approveAndDeposit(protectionPoolInstance, parseUSDC("55000"), user);

  // Deposit 2 by deployer
  await approveAndDeposit(protectionPoolInstance, parseUSDC("50000"), deployer);

  console.log("Pool's details ", await protectionPoolInstance.getPoolDetails());

  console.log("Completed min capital requirement.");

  // move the pool to the next phase
  await protectionPoolInstance.connect(deployer).movePoolPhase();

  console.log("********** Pool Phase: OpenToBuyers **********");

  const lendingPoolAddress = GOLDFINCH_LENDING_POOLS[0];

  // buy protection 1
  await transferApproveAndBuyProtection(
    protectionPoolInstance,
    {
      lendingPoolAddress: lendingPoolAddress,
      nftLpTokenId: BigNumber.from(590),
      protectionAmount: parseUSDC("150000"),
      protectionDurationInSeconds:
        PROTECTION_POOL_PARAMS.minProtectionDurationInSeconds
    },
    parseUSDC("35000")
  );

  console.log(
    "Pool's details after buyProtection",
    await protectionPoolInstance.getPoolDetails()
  );

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

  console.log("********** Pool Cycle: 2, Day: 31     **********");

  // Deposit 3
  await approveAndDeposit(protectionPoolInstance, parseUSDC("11000"), user);

  // Move pool to the next cycle (cycle 3)
  await movePoolCycle(
    protectionPoolInstance,
    protectionPoolCycleManagerInstance
  );

  console.log("********** Pool Cycle: 3, Day: 62     **********");

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

  console.log("Playground setup completed.");
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
  receiver: Signer
) {
  const usdcContract = getUsdcContract(receiver);
  const receiverAddress = await receiver.getAddress();

  // Approve & deposit
  await usdcContract.approve(protectionPoolInstance.address, depositAmt);
  return await protectionPoolInstance
    .connect(receiver)
    .deposit(depositAmt, receiverAddress);
}

async function transferApproveAndBuyProtection(
  protectionPoolInstance: ProtectionPool,
  purchaseParams: ProtectionPurchaseParamsStruct,
  maxPremiumAmt: BigNumber
) {
  // Update purchase params based on lending pool details
  const lendingPoolAddress = await purchaseParams.lendingPoolAddress;
  const lendingPoolDetails =
    PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS[
      lendingPoolAddress.toLowerCase()
    ];
  const buyer = await impersonateSignerWithEth(
    lendingPoolDetails.lendingPosition.owner,
    "10"
  );
  console.log("Buyer eth balance: ", formatEther(await buyer.getBalance()));
  purchaseParams.nftLpTokenId = lendingPoolDetails.lendingPosition.tokenId;

  const usdcContract = getUsdcContract(buyer);

  console.log(
    "Pool's details before buyProtection",
    await protectionPoolInstance.getPoolDetails()
  );

  console.log(
    "Using Lending pool position: ",
    lendingPoolDetails.lendingPosition
  );

  const buyerAddress = await buyer.getAddress();

  // transfer usdc to buyer, the lending position owner
  await transferUsdc(buyerAddress, maxPremiumAmt);

  // Approve premium USDC
  // todo: approve the exact premiumAmt after the buyProtection method with the premiumAmt argument is implemented
  await usdcContract
    .connect(buyer)
    .approve(protectionPoolInstance.address, maxPremiumAmt);

  console.log("Purchasing a protection using params: ", purchaseParams);

  return await protectionPoolInstance
    .connect(buyer)
    .buyProtection(purchaseParams, maxPremiumAmt);
}

(async () => {
  await deployAndSetup();
})().catch((err) => {
  console.error(err);
});
