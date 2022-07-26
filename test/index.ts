import { pool } from "./contracts/Pool.test";
import { poolFactory } from "./contracts/PoolFactory.test";
import { premiumPricing } from "./contracts/PremiumPricing.test";
import { tranche } from "./contracts/Tranche.test";
import { trancheFactory } from "./contracts/TrancheFactory.test";

import {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolInstance,
  poolFactoryInstance,
  referenceLoansInstance,
  trancheInstance,
  premiumPricingInstance
  trancheFactoryInstance
} from "../utils/deploy";

describe("start testing", () => {
  it("deploy contracts", async () => {
    await deployContracts();
  });

  it("run all the tests", () => {
    pool(account1, poolInstance, referenceLoansInstance);
    poolFactory(
      account1,
      poolFactoryInstance,
      premiumPricingInstance,
      referenceLoansInstance,
      trancheFactoryInstance
    );
    tranche(
      deployer,
      account1,
      account2,
      account3,
      premiumPricingInstance,
      trancheInstance
    );
    premiumPricing(deployer, premiumPricingInstance);
    trancheFactory(
      account1,
      trancheFactoryInstance,
      premiumPricingInstance,
      referenceLoansInstance
    );
  });
});
