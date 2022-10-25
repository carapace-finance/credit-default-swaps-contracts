import { Contract, Signer } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import {
  CIRCLE_ACCOUNT_ADDRESS,
  USDC_NUM_OF_DECIMALS,
  USDC_ADDRESS,
  USDC_ABI
} from "../utils/constants";
import { ethers } from "hardhat";

const formatUSDC: Function = (usdcAmt: BigNumber): string => {
  return formatUnits(usdcAmt, USDC_NUM_OF_DECIMALS);
};

const parseUSDC: Function = (usdcAmtText: string): BigNumber => {
  return parseUnits(usdcAmtText, USDC_NUM_OF_DECIMALS);
};

const getUsdcContract: Function = (signer: Signer) => {
  return new Contract(USDC_ADDRESS, USDC_ABI, signer);
};

const impersonateCircle: Function = async (): Promise<Signer> => {
  return await ethers.getImpersonatedSigner(CIRCLE_ACCOUNT_ADDRESS);
};

export { formatUSDC, parseUSDC, getUsdcContract, impersonateCircle };
