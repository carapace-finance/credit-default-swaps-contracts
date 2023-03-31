import { parseEther } from "ethers/lib/utils";

import { ProtectionPoolParamsStruct } from "../../typechain-types/contracts/interfaces/IProtectionPool";
import { ProtectionPoolCycleParamsStruct } from "../../typechain-types/contracts/interfaces/IProtectionPoolCycleManager";
import { getDaysInSeconds } from "../../test/utils/time";
import { parseUSDC } from "../../test/utils/usdc";

// List of lending pools from:
// https://docs.google.com/spreadsheets/d/1tkkZ_pL7PjGZ4Tw_IgPD76PSkn7hS1YsFCFb4jA1hiw/edit#gid=176360118
export const GOLDFINCH_LENDING_POOLS = [
  "0x418749e294cabce5a714efccc22a8aade6f9db57", // Almavest Basket #6
  "0xb26b42dd5771689d0a7faeea32825ff9710b9c11", // Lend East #1
  "0xd09a57127bc40d680be7cb061c2a6629fe71abef", // Cauris #2
  "0x759f097f3153f5d62ff1c2d82ba78b6350f223e3", // Almavest Basket #7
  "0xe6c30756136e07eb5268c3232efbfbe645c1ba5a", // Almavest Basket #4
  "0xc9bdd0d3b80cc6efe79a82d850f44ec9b55387ae", // Cauris #1
  "0x1d596d28a7923a22aa013b0e7082bba23daa656b", // Almavest Basket #5
  "0xefeb69edf6b6999b0e3f2fa856a2acf3bdea4ab5"  // Almavest Basket #3
];

// 0 = Goldfinch protocol
export const LENDING_POOL_PROTOCOLS = GOLDFINCH_LENDING_POOLS.map(pool => 0);

// Protocol params source: 
// https://docs.google.com/document/d/1iELOT2DXQFuU9jQXvQFw-QozmdivHyAmNHbnipH_MDY/edit#heading=h.gshbu9ougie6
export const LENDING_POOL_PURCHASE_LIMIT_IN_DAYS = GOLDFINCH_LENDING_POOLS.map(pool => 90);

export const PROTECTION_POOL_CYCLE_PARAMS: ProtectionPoolCycleParamsStruct = {
  openCycleDuration: getDaysInSeconds(7), // 1 week
  cycleDuration: getDaysInSeconds(90) // ~3 months
};

export const PROTECTION_POOL_PARAMS: ProtectionPoolParamsStruct = {
  leverageRatioFloor: parseEther("0.5"),
  leverageRatioCeiling: parseEther("1"),
  leverageRatioBuffer: parseEther("0.05"),
  minRequiredCapital: parseUSDC("1000000"), // 1M
  curvature: parseEther("0.05"),
  minCarapaceRiskPremiumPercent: parseEther("0.04"),
  underlyingRiskPremiumPercent: parseEther("0.1"),
  minProtectionDurationInSeconds: getDaysInSeconds(90),
  protectionRenewalGracePeriodInSeconds: getDaysInSeconds(10)
};

export const LATE_PAYMENT_GRACE_PERIOD_IN_DAYS = 15;
