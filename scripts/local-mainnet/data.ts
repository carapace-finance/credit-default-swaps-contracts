import { parseEther } from "ethers/lib/utils";

import { getDaysInSeconds } from "../../test/utils/time";
import { parseUSDC } from "../../test/utils/usdc";
import { ProtectionPoolParamsStruct } from "../../typechain-types/contracts/interfaces/IProtectionPool";
import { ProtectionPoolCycleParamsStruct } from "../../typechain-types/contracts/interfaces/IProtectionPoolCycleManager";

// Lending positions of pool can be found by looking at withdrawal txs in goldfinch app,
// then open it in etherscan and look at logs data for TokenRedeemed event
export const PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS: any = {
  // https://app.goldfinch.finance/pools/0xb26b42dd5771689d0a7faeea32825ff9710b9c11
  // Name: Lend East #1: Emerging Asia Fintech Pool
  // Payment date: 14 of every month
  // lending positions:
  // 645: 0x4902b20bb3b8e7776cbcdcb6e3397e7f6b4e449e, 158751.936393
  "0xb26b42dd5771689d0a7faeea32825ff9710b9c11": {
    name: "Lend East #1: Emerging Asia Fintech Pool",
    lendingPosition: {
      tokenId: 645,
      owner: "0x4902b20bb3b8e7776cbcdcb6e3397e7f6b4e449e"
    }
  },

  // https://app.goldfinch.finance/pools/0xd09a57127bc40d680be7cb061c2a6629fe71abef
  // Name: Cauris Fund #2: Africa Innovation Pool
  // Next repayment date: 21 of every month
  // lending positions:
  // 590: 0x008c84421da5527f462886cec43d2717b686a7e4  420,000.000000
  "0xd09a57127bc40d680be7cb061c2a6629fe71abef": {
    name: "Cauris Fund #2: Africa Innovation Pool",
    lendingPosition: {
      tokenId: 590,
      owner: "0x008c84421da5527f462886cec43d2717b686a7e4"
    }
  },

  // https://app.goldfinch.finance/pools/0x89d7c618a4eef3065da8ad684859a547548e6169
  // Next repayment date: 22 of every month
  // lending positions:
  // 717: 0x3371E5ff5aE3f1979074bE4c5828E71dF51d299c  808,000.000000
  "0x89d7c618a4eef3065da8ad684859a547548e6169": {
    name: "Asset-Backed Pool via Addem Capital",
    lendingPosition: {
      tokenId: 717,
      owner: "0x3371E5ff5aE3f1979074bE4c5828E71dF51d299c"
    }
  }
};

export const GOLDFINCH_LENDING_POOLS = Object.keys(
  PLAYGROUND_LENDING_POOL_DETAILS_BY_ADDRESS
);
export const LENDING_POOL_PROTOCOLS = GOLDFINCH_LENDING_POOLS.map(() => 0); // 0 = Goldfinch
export const LENDING_POOL_PURCHASE_LIMIT_IN_DAYS = GOLDFINCH_LENDING_POOLS.map(
  () => 270
);
export const PROTECTION_POOL_CYCLE_PARAMS: ProtectionPoolCycleParamsStruct = {
  openCycleDuration: getDaysInSeconds(7),
  cycleDuration: getDaysInSeconds(90)
};

export const PROTECTION_POOL_PARAMS: ProtectionPoolParamsStruct = {
  leverageRatioFloor: parseEther("0.5"),
  leverageRatioCeiling: parseEther("1"),
  leverageRatioBuffer: parseEther("0.05"),
  minRequiredCapital: parseUSDC("100000"), // 100k
  curvature: parseEther("0.05"),
  minCarapaceRiskPremiumPercent: parseEther("0.02"),
  underlyingRiskPremiumPercent: parseEther("0.1"),
  minProtectionDurationInSeconds: getDaysInSeconds(10),
  protectionRenewalGracePeriodInSeconds: getDaysInSeconds(14) // 2 weeks
};
