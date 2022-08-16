import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Signer } from "ethers";
import { USDC_ADDRESS } from "../utils/constants";
import { PremiumPricing } from "../../typechain-types/contracts/core/PremiumPricing";
import { ReferenceLoans } from "../../typechain-types/contracts/core/pool/ReferenceLoans";
import { TrancheFactory } from "../../typechain-types/contracts/core/TrancheFactory";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";

const testTrancheFactory: Function = (
  account1: Signer,
  pool: Pool,
  trancheFactory: TrancheFactory,
  premiumPricing: PremiumPricing,
  referenceLoans: ReferenceLoans,
  poolCycleManager: PoolCycleManager
) => {
  describe("TrancheFactory", () => {
    describe("createTranche", async () => {
      const _firstPoolFirstTrancheSalt: string = "0x".concat(
        process.env.FIRST_POOL_FIRST_TRANCHE_SALT
      );
      const _firstPoolSecondTrancheSalt: string = "0x".concat(
        process.env.FIRST_POOL_SECOND_TRANCHE_SALT
      );
      const _firstPoolId: BigNumber = BigNumber.from(1);

      it("...only the owner should be able to call the createTranche function", async () => {
        await expect(
          trancheFactory
            .connect(account1)
            .createTranche(
              _firstPoolFirstTrancheSalt,
              _firstPoolId,
              pool.address,
              "sToken11",
              "sT11",
              USDC_ADDRESS,
              referenceLoans.address,
              premiumPricing.address,
              poolCycleManager.address,
              { gasLimit: 100000 }
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...the pool id 1 should be empty", async () => {
        expect(await trancheFactory.poolIdToTrancheIdCounter(1)).to.equal("0");
      });

      it("...create the first tranche in the first pool", async () => {
        await expect(
          trancheFactory.createTranche(
            _firstPoolSecondTrancheSalt,
            _firstPoolId,
            pool.address,
            "sToken11",
            "sT11",
            USDC_ADDRESS,
            referenceLoans.address,
            premiumPricing.address,
            poolCycleManager.address
          )
        )
          .to.emit(trancheFactory, "TrancheCreated")
          .withArgs(
            _firstPoolId,
            "sToken11",
            "sT11",
            USDC_ADDRESS,
            referenceLoans.address
          );
      });

      it("...should increment the tranche id counter for a given pool id", async () => {
        expect(await trancheFactory.poolIdToTrancheIdCounter(1)).to.equal("2");
      });

      it("...create the second tranche in the first pool", async () => {
        expect(
          await trancheFactory.createTranche(
            _firstPoolSecondTrancheSalt,
            _firstPoolId,
            pool.address,
            "sToken12",
            "sT12",
            USDC_ADDRESS,
            referenceLoans.address,
            premiumPricing.address,
            poolCycleManager.address
          )
        )
          .to.emit(trancheFactory, "TrancheCreated")
          .withArgs(
            _firstPoolId,
            "sToken12",
            "sT12",
            USDC_ADDRESS,
            referenceLoans.address
          );
      });

      it("...should increment the tranche id counter for a given pool id", async () => {
        expect(await trancheFactory.poolIdToTrancheIdCounter(1)).to.equal("3");
      });
    });
  });
};

export { testTrancheFactory };
