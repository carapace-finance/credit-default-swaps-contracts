import { tranche } from "./contracts/Tranche.test";
import { pool } from "./contracts/Pool.test";
import { poolFactory } from "./contracts/PoolFactory.test";
import { premiumPricing } from "./contracts/PremiumPricing.test";
import {
  deployer,
  account1,
  account2,
  account3,
  account4,
  deployContracts,
  poolInstance,
  poolFactoryInstance,
  trancheInstance,
  premiumPricingInstance
} from "../utils/deploy";

describe("start testing", () => {
  it("deploy contracts", async () => {
    await deployContracts();
  });

  it("run all the tests", () => {
    pool(account1, poolInstance, referenceLoansInstance);
    poolFactory(
      deployer,
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
  });
});
