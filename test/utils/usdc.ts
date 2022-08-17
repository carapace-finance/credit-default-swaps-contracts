import { BigNumber } from "@ethersproject/bignumber";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { USDC_NUM_OF_DECIMALS } from "./constants";

const formatUSDC: Function = (usdcAmt: BigNumber): string => {
  return formatUnits(usdcAmt, USDC_NUM_OF_DECIMALS);
};

const parseUSDC: Function = (usdcAmtText: string): BigNumber => {
  return parseUnits(usdcAmtText, USDC_NUM_OF_DECIMALS);
};

export { formatUSDC, parseUSDC };
