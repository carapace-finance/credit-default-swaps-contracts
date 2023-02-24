import { deployContracts } from "../../utils/deploy";
import {
  PROTECTION_POOL_CYCLE_PARAMS,
  PROTECTION_POOL_PARAMS,
  GOLDFINCH_LENDING_POOLS,
  LENDING_POOL_PROTOCOLS,
  LENDING_POOL_PURCHASE_LIMIT_IN_DAYS
} from "../../test/test-data";

(async () => {
  await deployContracts(
    PROTECTION_POOL_CYCLE_PARAMS,
    PROTECTION_POOL_PARAMS,
    GOLDFINCH_LENDING_POOLS,
    LENDING_POOL_PROTOCOLS,
    LENDING_POOL_PURCHASE_LIMIT_IN_DAYS
  );
})().catch((err) => {
  console.error(err);
});
