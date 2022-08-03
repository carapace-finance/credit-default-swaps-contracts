import { BigNumber } from "@ethersproject/bignumber";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { Signer } from "ethers";
import { USDC_ADDRESS } from "../utils/constants";
import { PremiumPricing } from "../../typechain-types/contracts/core/PremiumPricing";
import { PoolFactory } from "../../typechain-types/contracts/core/PoolFactory";
import { ReferenceLoans } from "../../typechain-types/contracts/core/pool/ReferenceLoans";
import { TrancheFactory } from "../../typechain-types/contracts/core/TrancheFactory";
import { ethers } from "hardhat";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";

const testPoolFactory: Function = (
  account1: Signer,
  poolFactory: PoolFactory,
  premiumPricing: PremiumPricing,
  referenceLoans: ReferenceLoans,
  trancheFactory: TrancheFactory
) => {
  describe("PoolFactory", () => {
    describe("createPool", async () => {
      const _firstPoolFirstTrancheSalt: string = "0x".concat(
        process.env.FIRST_POOL_FIRST_TRANCHE_SALT
      );
      const _secondPoolFirstTrancheSalt: string = "0x".concat(
        process.env.SECOND_POOL_FIRST_TRANCHE_SALT
      );
      const _floor: BigNumber = BigNumber.from(100);
      const _ceiling: BigNumber = BigNumber.from(500);
      const _firstPoolId: BigNumber = BigNumber.from(1);
      const _secondPoolId: BigNumber = BigNumber.from(2);

      it("...only the owner should be able to call the createPool function", async () => {
        await expect(
          poolFactory
            .connect(account1)
            .createPool(
              _firstPoolFirstTrancheSalt,
              _floor,
              _ceiling,
              USDC_ADDRESS,
              referenceLoans.address,
              premiumPricing.address,
              "sToken11",
              "sT11",
              { gasLimit: 100000 }
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...fail if the floor is", async () => {
        // todo: write this test with the error and revert
      });

      it("...fail if the ceiling is", async () => {
        // todo: write this test with the error and revert
      });

      it("...create the first pool and tranche", async () => {
        expect(
          await poolFactory.createPool(
            _firstPoolFirstTrancheSalt,
            _floor,
            _ceiling,
            USDC_ADDRESS,
            referenceLoans.address,
            premiumPricing.address,
            "sToken11",
            "sT11"
          )
        )
          .to.emit(poolFactory, "PoolCreated")
          .withArgs(
            _firstPoolId,
            _floor,
            _ceiling,
            USDC_ADDRESS,
            referenceLoans.address,
            premiumPricing.address
          )
          .to.emit(poolFactory, "PoolCycleCreated")
          .withArgs(
            _firstPoolId,
            0,
            anyValue,
            poolFactory.POOL_OPEN_CYCLE_DURATION,
            poolFactory.POOL_CYCLE_DURATION
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

      it("...the poolId 0 should be empty", async () => {
        expect(await poolFactory.poolIdToPoolAddress(0)).to.equal(
          "0x0000000000000000000000000000000000000000"
        );
      });

      it("...should increment the pool id counter", async () => {
        expect(await poolFactory.poolIdCounter()).equal(2);
      });

      it("...create the second pool and tranche", async () => {
        expect(
          await poolFactory.createPool(
            _secondPoolFirstTrancheSalt,
            _floor,
            _ceiling,
            USDC_ADDRESS,
            referenceLoans.address,
            premiumPricing.address,
            "sToken21",
            "sT21"
          )
        )
          .to.emit(poolFactory, "PoolCreated")
          .withArgs(
            _secondPoolId,
            _floor,
            _ceiling,
            USDC_ADDRESS,
            referenceLoans.address,
            premiumPricing.address
          )
          .to.emit(poolFactory, "PoolCycleCreated")
          .withArgs(
            _secondPoolId,
            0,
            anyValue,
            poolFactory.POOL_OPEN_CYCLE_DURATION,
            poolFactory.POOL_CYCLE_DURATION
          )
          .to.emit(trancheFactory, "TrancheCreated")
          .withArgs(
            _secondPoolId,
            "sToken21",
            "sT21",
            USDC_ADDRESS,
            referenceLoans.address
          );
      });

      it("...should start new pool cycles for created pools", async () => {
        const poolCycleManager: PoolCycleManager = (await ethers.getContractAt("PoolCycleManager", await poolFactory.poolCycleManager())) as PoolCycleManager;
        
        expect(await poolCycleManager.getCurrentCycleIndex(_firstPoolId)).to.equal(0);
        expect(await poolCycleManager.getCurrentCycleState(_firstPoolId)).to.equal(1);  // 1 = Open

        expect(await poolCycleManager.getCurrentCycleIndex(_secondPoolId)).to.equal(0);
        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(1);  // 1 = Open
        expect((await poolCycleManager.poolCycles(_secondPoolId)).currentCycleStartTime)
          .to.equal((await ethers.provider.getBlock("latest")).timestamp);
      });

      // todo: test the generated address after implementing the address pre-computation method in solidity
      // it("...the second pool address should match the second pool address in the poolIdToPoolAddress", async () => {
      //   const secondPoolAddress = await poolFactory.callStatic.createPool(
      //     _secondPoolFirstTrancheSalt,
      //     _floor,
      //     _ceiling,
      //     USDC_ADDRESS,
      //     referenceLoans.address,
      //     premiumPricing.address,
      //     "sToken21",
      //     "sT21"
      //   );
      //   expect(secondPoolAddress).to.equal(
      //     await poolFactory.poolIdToPoolAddress(2)
      //   );
      // });
    });
  });
};

export { testPoolFactory };

