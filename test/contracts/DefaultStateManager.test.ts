import { DefaultStateManager } from "../../typechain-types/contracts/core/DefaultStateManager";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ZERO_ADDRESS } from "../utils/constants";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { PoolFactory } from "../../typechain-types/contracts/core/PoolFactory";
import { ethers } from "hardhat";
import { parseUSDC, getUsdcContract, impersonateCircle } from "../utils/usdc";
import { parseEther } from "ethers/lib/utils";
import { moveForwardTimeByDays } from "../utils/time";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";

const testDefaultStateManager: Function = (
  deployer: Signer,
  account1: Signer,
  seller: Signer,
  defaultStateManager: DefaultStateManager,
  poolFactory: PoolFactory,
  poolInstance: Pool,
  lendingPools: string[]
) => {
  describe("DefaultStateManager", () => {
    let usdcContract: Contract;
    let lendingPool2: ITranchedPool;
    let pool1: string;
    let pool2: string;
    let sellerAddress: string;

    const payToLendingPool: Function = async (
      tranchedPool: ITranchedPool,
      amount: string
    ) => {
      const amountToPay = parseUSDC(amount);

      // Transfer USDC to lending pool's credit line
      await usdcContract
        .connect(await impersonateCircle())
        .transfer(await tranchedPool.creditLine(), amountToPay.toString());

      // assess lending pool
      await tranchedPool.assess();
    };

    before(async () => {
      lendingPool2 = (await ethers.getContractAt(
        "ITranchedPool",
        lendingPools[1]
      )) as ITranchedPool;

      usdcContract = getUsdcContract(deployer);
      pool1 = poolInstance.address;
      pool2 = await poolFactory.poolIdToPoolAddress(2);
      sellerAddress = await seller.getAddress();
    });

    describe("constructor", async () => {
      it("...should have dummy pool state at index 0", async () => {
        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(ZERO_ADDRESS)
        ).to.equal(0);
      });
    });

    describe("registerPool", async () => {
      it("...should NOT be callable by non-pool-factory address", async () => {
        await expect(
          defaultStateManager.connect(account1).registerPool(ZERO_ADDRESS)
        ).to.be.revertedWith(
          `NotPoolFactory("${await account1.getAddress()}")`
        );
      });

      it("...should fail to register already registered pool", async () => {
        await expect(
          defaultStateManager
            .connect(await ethers.getSigner(poolFactory.address))
            .registerPool(poolInstance.address)
        ).to.be.revertedWith(
          `PoolAlreadyRegistered("${await poolInstance.address}")`
        );
      });

      it("...should have update timestamp for registered pool", async () => {
        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1)
        ).to.be.gt(0);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2)
        ).to.be.gt(0);
      });
    });

    describe("assessStates", async () => {
      it("...should update states for registered pools", async () => {
        const pool1UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1);
        const pool2UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2);

        await expect(defaultStateManager.assessStates()).to.emit(
          defaultStateManager,
          "PoolStatesAssessed"
        );

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1)
        ).to.be.gt(pool1UpdateTimestamp);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2)
        ).to.be.gt(pool2UpdateTimestamp);
      });
    });

    describe("assessState", async () => {
      it("...should update state for specified registered pool", async () => {
        const pool1UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1);
        const pool2UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2);

        await defaultStateManager.assessState(pool1);
        await defaultStateManager.assessState(pool2);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1)
        ).to.be.gt(pool1UpdateTimestamp);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2)
        ).to.be.gt(pool2UpdateTimestamp);
      });
    });

    describe("state transition from active -> late", async () => {
      it("...should lock capital for both lending pools in pool 1", async () => {
        await moveForwardTimeByDays(30);
        await defaultStateManager.assessStates();

        // Verify that both lending pools in Pool 1 are in late state and has locked capital instances
        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);

        expect(lockedCapitalsLendingPool1.length).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].snapshotId).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].amount).to.eq(0);
        expect(lockedCapitalsLendingPool1[0].locked).to.eq(true);

        const lockedCapitalsLendingPool2 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[1]);

        expect(lockedCapitalsLendingPool2.length).to.eq(1);
        expect(lockedCapitalsLendingPool2[0].snapshotId).to.eq(2);

        // pool doesn't have enough capital, so total sTokenUnderlying is locked
        expect(lockedCapitalsLendingPool2[0].amount).to.be.gt(
          parseUSDC("1000")
        );
        expect(lockedCapitalsLendingPool2[0].locked).to.eq(true);
      });
    });

    describe("state transition from late -> active", async () => {
      before(async () => {
        // payment to lending pool
        await payToLendingPool(lendingPool2, "100000");

        // deposit by account1
        // const _underlyingAmount = parseUSDC("1500");
        // await usdcContract
        //   .connect(account1)
        //   .approve(poolInstance.address, _underlyingAmount);
        // await poolInstance
        //   .connect(account1)
        //   .deposit(_underlyingAmount, await account1.getAddress());

        await defaultStateManager.assessStates();
      });

      describe("calculateClaimableUnlockedAmount", async () => {
        it("...should return 0 claimable amount for deployer from pool 1", async () => {
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              await deployer.getAddress()
            )
          ).to.eq(0);
        });

        it("...should return ~1000 claimable amount for seller from pool 1", async () => {
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              sellerAddress
            )
          )
            .to.be.gt(parseUSDC("1000"))
            .and.to.be.lt(parseUSDC("1001"));
        });

        // enable this test after anytime deposit is enabled
        // it("...should return ~1500 claimable amount for account 1 from pool 1", async () => {
        //   expect(
        //     await defaultStateManager.calculateClaimableUnlockedAmount(
        //       pool1,
        //       await account1.getAddress()
        //     )
        //   )
        //     .to.be.gt(parseUSDC("1500"))
        //     .and.to.be.lt(parseUSDC("1501"));
        // });
      });

      describe("calculateAndClaimUnlockedCapital", async () => {
        it("...should revert when called from non-pool address", async () => {
          await expect(
            defaultStateManager.calculateAndClaimUnlockedCapital(sellerAddress)
          ).to.be.revertedWith(
            `PoolNotRegistered("Only registered pools can claim unlocked capital")`
          );
        });
      });
    });
  });
};

export { testDefaultStateManager };
