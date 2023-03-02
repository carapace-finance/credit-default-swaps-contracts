import { parseUSDC, impersonateCircle } from "../utils/usdc";
import { BigNumber, Contract, Signer } from "ethers";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";
import { IPoolTokens } from "../../typechain-types/contracts/external/goldfinch/IPoolTokens";
import { ethers } from "hardhat";
import { impersonateSignerWithEth } from "./utils";

// Address of Goldfinch's PoolTokens contract
const POOL_TOKENS_ADDRESS: string =
  "0x57686612C601Cb5213b01AA8e80AfEb24BBd01df";

const payToLendingPool: Function = async (
  tranchedPool: ITranchedPool,
  amount: string,
  usdcContract: Contract
) => {
  const amountToPay = parseUSDC(amount);

  // Transfer USDC to lending pool's credit line
  await usdcContract
    .connect(await impersonateCircle())
    .transfer(await tranchedPool.creditLine(), amountToPay.toString());

  // assess lending pool
  await tranchedPool.assess();
};

const payToLendingPoolAddress: Function = async (
  tranchedPoolAddress: string,
  usdcAmount: string,
  usdcContract: Contract
) => {
  const tranchedPool = (await ethers.getContractAt(
    "ITranchedPool",
    tranchedPoolAddress
  )) as ITranchedPool;

  await payToLendingPool(tranchedPool, usdcAmount, usdcContract);
};

// 420K principal for token 590
const getGoldfinchLender1: Function = async (): Promise<Signer> => {
  return await ethers.getImpersonatedSigner(
    "0x008c84421da5527f462886cec43d2717b686a7e4"
  );
};

const getPoolTokensContract: Function = async (): Promise<IPoolTokens> => {
  return (await ethers.getContractAt(
    "IPoolTokens",
    POOL_TOKENS_ADDRESS
  )) as IPoolTokens;
};

/**
 * Transfers a lending position represented by the given tokenId from to to address.
 * @param from
 * @param to
 * @param tokenId
 * @returns
 */
const transferLendingPosition: Function = async (
  from: string,
  to: string,
  tokenId: BigNumber
) => {
  const poolTokensContract = await getPoolTokensContract();
  const fromSigner = await impersonateSignerWithEth(from);
  return await poolTokensContract
    .connect(fromSigner)
    .transferFrom(from, to, tokenId);
};

export {
  payToLendingPool,
  payToLendingPoolAddress,
  getGoldfinchLender1,
  getPoolTokensContract,
  transferLendingPosition
};
