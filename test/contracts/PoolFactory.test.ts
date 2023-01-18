import { BigNumber } from "@ethersproject/bignumber";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { parseEther } from "ethers/lib/utils";
import { expect } from "chai";
import { Signer } from "ethers";
import { USDC_ADDRESS, ZERO_ADDRESS } from "../utils/constants";
import { ethers } from "hardhat";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import {
  PoolParamsStruct,
  PoolCycleParamsStruct
} from "../../typechain-types/contracts/interfaces/IPool";
import { Pool } from "../../typechain-types/contracts/core/Pool";
import { PremiumCalculator } from "../../typechain-types/contracts/core/PremiumCalculator";
import { PoolFactory } from "../../typechain-types/contracts/core/PoolFactory";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { DefaultStateManager } from "../../typechain-types/contracts/core/DefaultStateManager";
import { parseUSDC } from "../utils/usdc";
import { getDaysInSeconds, getLatestBlockTimestamp } from "../utils/time";

const testPoolFactory: Function = (
  deployer: Signer,
  account1: Signer,
  poolFactory: PoolFactory,
  premiumCalculator: PremiumCalculator,
  referenceLendingPools: ReferenceLendingPools,
  poolCycleManager: PoolCycleManager,
  defaultStateManager: DefaultStateManager,
  poolImplementation: Pool
) => {
  describe("PoolFactory", () => {
    let _firstPoolAddress: string;
    let _secondPoolAddress: string;

    before(async () => {
      _firstPoolAddress = (await poolFactory.getPools())[0];
      console.log("first pool address", _firstPoolAddress);
    });

    describe("createPool", async () => {
      const poolCycleParams: PoolCycleParamsStruct = {
        openCycleDuration: BigNumber.from(10 * 86400), // 10 days
        cycleDuration: BigNumber.from(30 * 86400) // 30 days
      };
      const _floor: BigNumber = BigNumber.from(100);
      const _ceiling: BigNumber = BigNumber.from(500);
      const _poolParams: PoolParamsStruct = {
        leverageRatioFloor: _floor,
        leverageRatioCeiling: _ceiling,
        leverageRatioBuffer: BigNumber.from(5),
        minRequiredCapital: parseUSDC("10000"),
        curvature: BigNumber.from(5),
        minCarapaceRiskPremiumPercent: parseEther("0.02"),
        underlyingRiskPremiumPercent: parseEther("0.1"),
        minProtectionDurationInSeconds: getDaysInSeconds(10),
        poolCycleParams: poolCycleParams,
        protectionExtensionGracePeriodInSeconds: getDaysInSeconds(14) // 2 weeks
      };

      it("...only the owner should be able to call the createPool function", async () => {
        await expect(
          poolFactory
            .connect(account1)
            .createPool(
              poolImplementation.address,
              _poolParams,
              USDC_ADDRESS,
              referenceLendingPools.address,
              premiumCalculator.address,
              "sToken11",
              "sT11",
              { gasLimit: 100000 }
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...should have started a new pool cycle for 1st pool created", async () => {
        expect(
          await poolCycleManager.getCurrentCycleIndex(_firstPoolAddress)
        ).to.equal(0);
        expect(
          await poolCycleManager.getCurrentCycleState(_firstPoolAddress)
        ).to.equal(1); // 1 = Open
      });

      // 1st pool is already created by deploy script
      it("...create the second pool", async () => {
        const expectedCycleStartTimestamp: BigNumber =
          (await getLatestBlockTimestamp()) + 1;

        await expect(
          poolFactory.createPool(
            poolImplementation.address,
            _poolParams,
            USDC_ADDRESS,
            referenceLendingPools.address,
            premiumCalculator.address,
            "sToken21",
            "sT21"
          )
        )
          .to.emit(poolFactory, "PoolCreated")
          .withArgs(
            _secondPoolAddress,
            anyValue,
            _floor,
            _ceiling,
            USDC_ADDRESS,
            referenceLendingPools.address,
            premiumCalculator.address
          )
          // Newly created pool should be registered to PoolCycleManager
          .to.emit(poolCycleManager, "PoolCycleCreated")
          .withArgs(
            _secondPoolAddress,
            0,
            expectedCycleStartTimestamp,
            poolCycleParams.openCycleDuration,
            poolCycleParams.cycleDuration
          )
          .emit(defaultStateManager, "PoolRegistered");

        _secondPoolAddress = (await poolFactory.getPools())[1];
      });

      it("...should start new pool cycle for the second pool", async () => {
        expect(
          await poolCycleManager.getCurrentCycleIndex(_secondPoolAddress)
        ).to.equal(0);
        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(1); // 1 = Open
        expect(
          (await poolCycleManager.poolCycles(_secondPoolAddress))
            .currentCycleStartTime
        ).to.equal((await ethers.provider.getBlock("latest")).timestamp);
      });

      it("...should transfer pool's ownership to poolFactory's owner", async () => {
        const deployerAddress: string = await deployer.getAddress();
        expect(poolFactory)
          .to.emit(poolFactory, "OwnershipTransferred")
          .withArgs(poolFactory.address, deployerAddress);

        const secondPool: Pool = (await ethers.getContractAt(
          "Pool",
          _secondPoolAddress
        )) as Pool;
        expect(await secondPool.owner()).to.equal(deployerAddress);
      });
    });
  });
};

export { testPoolFactory };
