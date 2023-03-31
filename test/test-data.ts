import { parseEther } from "ethers/lib/utils";

import { ProtectionPoolParamsStruct } from "../typechain-types/contracts/interfaces/IProtectionPool";
import { ProtectionPoolCycleParamsStruct } from "../typechain-types/contracts/interfaces/IProtectionPoolCycleManager";
import { getDaysInSeconds } from "./utils/time";
import { parseUSDC } from "./utils/usdc";

export const GOLDFINCH_LENDING_POOLS = [
  "0xb26b42dd5771689d0a7faeea32825ff9710b9c11",
  "0xd09a57127bc40d680be7cb061c2a6629fe71abef"
];
export const LENDING_POOL_PROTOCOLS = [0, 0]; // 0 = Goldfinch
export const LENDING_POOL_PURCHASE_LIMIT_IN_DAYS = [90, 60];

export const PROTECTION_POOL_CYCLE_PARAMS: ProtectionPoolCycleParamsStruct = {
  openCycleDuration: getDaysInSeconds(10),
  cycleDuration: getDaysInSeconds(30)
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

export const LATE_PAYMENT_GRACE_PERIOD_IN_DAYS = 7;