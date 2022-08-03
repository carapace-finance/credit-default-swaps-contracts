import { BigNumber } from "@ethersproject/bignumber";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { assert } from "console";
import { Signer } from "ethers";
import { ethers } from "hardhat";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import { moveForwardTime } from "../utils/time";

const testPoolCycleManager: Function = (
  deployer: Signer,
  account1: Signer,
  poolCycleManager: PoolCycleManager
) => {
  describe("PoolCycleManager", () => {
    const _firstPoolId: BigNumber = BigNumber.from(1);
    const _secondPoolId: BigNumber = BigNumber.from(2);
    const _openCycleDuration: BigNumber = BigNumber.from(7 * 24 * 60 * 60);  // 7 days
    const _cycleDuration: BigNumber = BigNumber.from(30 * 24 * 60 * 60);  // 30 days

    describe("registerPool", async () => {
      it("...should NOT be able to callable by non-owner", async () => {
        await expect(
          poolCycleManager
            .connect(account1)
            .registerPool(
              _firstPoolId,
              _openCycleDuration,
              _cycleDuration,
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...should be able callable by only owner", async () => {
        await expect(
          poolCycleManager
            .registerPool(
              _firstPoolId,
              _openCycleDuration,
              _cycleDuration
            )
        ).to.emit(poolCycleManager, "PoolCycleCreated")
          .withArgs(_firstPoolId, 0, anyValue, _openCycleDuration, _cycleDuration);
      });

      it("...should NOT be able to register pool twice", async () => {
        await expect(
          poolCycleManager
            .registerPool(
              _firstPoolId,
              _openCycleDuration,
              _cycleDuration,
            )
        ).to.be.revertedWith(`PoolAlreadyRegistered(${_firstPoolId})`);
      });

      it("...should NOT be able to register pool with openCycleduration > cycleDuration", async () => {
        await expect(
          poolCycleManager
            .registerPool(
              _secondPoolId,
              _openCycleDuration.add(_cycleDuration),
              _cycleDuration
            )
        ).to.be.revertedWith(`InvalidCycleDuration(${_cycleDuration})`);
      });

      it("...should create new cycle for the pool with correct params", async () => {
        await poolCycleManager
          .connect(deployer)
          .registerPool(_secondPoolId, _openCycleDuration, _cycleDuration);
        
        expect(await poolCycleManager.getCurrentCycleIndex(_secondPoolId)).to.equal(0);
        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(1);  // 1 = Open
        
        const poolCycle = await poolCycleManager.poolCycles(_secondPoolId);
        expect(poolCycle.openCycleDuration).to.equal(_openCycleDuration);
        expect(poolCycle.cycleDuration).to.equal(_cycleDuration);
        expect(poolCycle.currentCycleStartTime).to.equal((await ethers.provider.getBlock("latest")).timestamp);
      });
    });

    describe("calculateAndSetPoolCycleState", async () => {
      let cycleStartTime: BigNumber;
      before(async () => {
        cycleStartTime = (await poolCycleManager.poolCycles(_secondPoolId)).currentCycleStartTime;
      });

      it("...should have 'Created' state for non-registered pool", async () => {
        await poolCycleManager.calculateAndSetPoolCycleState(3);
        expect(await poolCycleManager.getCurrentCycleState(3)).to.equal(0);  // 0 = None
      });
      
      it("...should stay in 'Open' state when less time than openCycleDuration has passed", async () => {
        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(1);  // 1 = Open

        // Move time forward by openCycleDuration - 30 seconds
        await moveForwardTime(_openCycleDuration.sub(30));
        
        // Verify current time is less than cycleStartTime + openCycleDuration
        const currentTime = BigNumber.from((await ethers.provider.getBlock("latest")).timestamp);
        assert(currentTime < cycleStartTime.add(_openCycleDuration));

        await poolCycleManager.calculateAndSetPoolCycleState(_secondPoolId);

        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(1);  // 1 = Open
        expect(await poolCycleManager.getCurrentCycleIndex(_secondPoolId)).to.equal(0);
      });

      it("...should move to 'Locked' state after openCycleDuration has passed", async () => {
        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(1);  // 1 = Open

        // Move time forward by time left in openCycleDuration
        await moveForwardTime(BigNumber.from(30));
        
        // Verify current time is greater than cycleStartTime + openCycleDuration
        const currentTime = BigNumber.from((await ethers.provider.getBlock("latest")).timestamp);
        assert(currentTime > cycleStartTime.add(_openCycleDuration));

        await poolCycleManager.calculateAndSetPoolCycleState(_secondPoolId);

        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(2);  // 2 = Locked
        expect(await poolCycleManager.getCurrentCycleIndex(_secondPoolId)).to.equal(0);
      });

      it("...should stay in 'Locked' state when less time than cycleDuration has passed", async () => {
        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(2);  // 2 = Locked

        // Move time forward by cycleDuration - 30 seconds
        const lessThanCycleDuration = _cycleDuration.sub(_openCycleDuration).sub(30);
        await moveForwardTime(lessThanCycleDuration);
        
        // Verify current time is less than cycleStartTime + cycleDuration
        const currentTime = BigNumber.from((await ethers.provider.getBlock("latest")).timestamp);
        assert(currentTime < cycleStartTime.add(_cycleDuration));

        await poolCycleManager.calculateAndSetPoolCycleState(_secondPoolId);

        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(2);  // 2 = Locked
        expect(await poolCycleManager.getCurrentCycleIndex(_secondPoolId)).to.equal(0);
      });

      it("...should create new cycle with 'Open' state after cycleDuration has passed", async () => {
        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(2);  // 2 = Locked

        // Move time forward by time left in cycle
        await moveForwardTime(BigNumber.from(30));
        
        await poolCycleManager.calculateAndSetPoolCycleState(_secondPoolId);

        // Verify current time is greater than cycleStartTime + cycleDuration
        const currentTime = BigNumber.from((await ethers.provider.getBlock("latest")).timestamp);
        assert(currentTime > cycleStartTime.add(_cycleDuration));

        expect(await poolCycleManager.getCurrentCycleState(_secondPoolId)).to.equal(1);  // 1 = Open
        expect(await poolCycleManager.getCurrentCycleIndex(_secondPoolId)).to.equal(1);
      });
    });
  });
};

export { testPoolCycleManager };