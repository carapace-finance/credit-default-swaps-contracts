import { ethers } from "hardhat";
import hre from "hardhat";

import { deployContracts } from "../../utils/deploy";
import {
  PROTECTION_POOL_CYCLE_PARAMS,
  PROTECTION_POOL_PARAMS,
  GOLDFINCH_LENDING_POOLS,
  LENDING_POOL_PROTOCOLS,
  LENDING_POOL_PURCHASE_LIMIT_IN_DAYS,
  LATE_PAYMENT_GRACE_PERIOD_IN_DAYS
} from "./prod-data";

(async () => {
  // create new ethers wallet using default provider
  const operator = new ethers.Wallet(
    "0x" + process.env.OPERATOR_PRIVATE_KEY,
    hre.ethers.provider
  );

  await deployContracts(
    PROTECTION_POOL_CYCLE_PARAMS,
    PROTECTION_POOL_PARAMS,
    GOLDFINCH_LENDING_POOLS,
    LENDING_POOL_PROTOCOLS,
    LENDING_POOL_PURCHASE_LIMIT_IN_DAYS,
    LATE_PAYMENT_GRACE_PERIOD_IN_DAYS,
    operator,
    false,      // useMock
    "sToken1",  // sToken name
    "ST1",      // sToken symbol
  );
})().catch((err) => {
  console.error(err);
});
