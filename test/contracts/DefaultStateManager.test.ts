import { DefaultStateManager } from "../../typechain-types/contracts/core/DefaultStateManager";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ZERO_ADDRESS } from "../utils/constants";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { PoolFactory } from "../../typechain-types/contracts/core/PoolFactory";
import { ethers } from "hardhat";
import {
  parseUSDC,
  getUsdcContract,
  transferAndApproveUsdc
} from "../utils/usdc";
import {
  getDaysInSeconds,
  getLatestBlockTimestamp,
  moveForwardTimeByDays,
  setNextBlockTimestamp
} from "../utils/time";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";
import { payToLendingPool } from "../utils/goldfinch";
import { BigNumber } from "@ethersproject/bignumber";
import { getGoldfinchLender1 } from "../utils/goldfinch";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/Pool";

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
    let referenceLendingPoolsInstance: ReferenceLendingPools;

    before(async () => {
      lendingPool2 = (await ethers.getContractAt(
        "ITranchedPool",
        lendingPools[1]
      )) as ITranchedPool;

      usdcContract = getUsdcContract(deployer);
      pool1 = poolInstance.address;
      pool2 = await poolFactory.getPoolAddress(2);
      sellerAddress = await seller.getAddress();

      referenceLendingPoolsInstance = (await ethers.getContractAt(
        "ReferenceLendingPools",
        (
          await poolInstance.getPoolInfo()
        ).referenceLendingPools
      )) as ReferenceLendingPools;
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

    describe("assessStateBatch", async () => {
      it("...should update state for specified registered pool", async () => {
        const pool1UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1);
        const pool2UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2);

        await defaultStateManager.assessStateBatch([pool1]);
        await defaultStateManager.assessStateBatch([pool2]);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1)
        ).to.be.gt(pool1UpdateTimestamp);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2)
        ).to.be.gt(pool2UpdateTimestamp);
      });
    });

    describe("state transition from active -> late", async () => {
      const depositToPool = async (
        _account: Signer,
        _depositAmount: BigNumber
      ) => {
        const _accountAddress = await _account.getAddress();
        await transferAndApproveUsdc(
          _account,
          _depositAmount,
          poolInstance.address
        );
        await poolInstance
          .connect(_account)
          .deposit(_depositAmount, _accountAddress);
      };

      before(async () => {
        // deposit capital into pool
        await depositToPool(seller, parseUSDC("50000"));
        await depositToPool(account1, parseUSDC("50000"));

        expect(await poolInstance.totalSTokenUnderlying()).to.equal(
          parseUSDC("100000")
        );

        // we need to movePoolPhase
        await poolInstance.connect(deployer).movePoolPhase();
        // Pool should be in OpenToBuyers phase
        expect((await poolInstance.getPoolInfo()).currentPhase).to.eq(1);

        // Buy protection
        const _protection_buyer = await getGoldfinchLender1();
        await usdcContract
          .connect(_protection_buyer)
          .approve(poolInstance.address, parseUSDC("3000"));
        await poolInstance.connect(_protection_buyer).buyProtection({
          lendingPoolAddress: lendingPools[1],
          nftLpTokenId: 590,
          protectionAmount: parseUSDC("20000"),
          protectionDurationInSeconds: getDaysInSeconds(20)
        });

        // await moveForwardTimeByDays(30);
        // Move time forward by 30 days from last payment timestamp

        // 1663351858 = Fri Sep 16 2022 13:10:58 GMT-0500 (Central Daylight Time)
        const lastPaymentTimestamp1 =
          await referenceLendingPoolsInstance.getLatestPaymentTimestamp(
            lendingPools[0]
          );

        // 1663899496 = Thu Sep 22 2022 21:18:16 GMT-0500 (Central Daylight Time)
        const lastPaymentTimestamp2 =
          await referenceLendingPoolsInstance.getLatestPaymentTimestamp(
            lendingPools[1]
          );
        console.log(
          "lastPaymentTimestamp for lending pool 2",
          lastPaymentTimestamp2.toString()
        );

        // 1666491496
        const lastPaymentTimestamp = lastPaymentTimestamp1.gt(
          lastPaymentTimestamp2
        )
          ? lastPaymentTimestamp1
          : lastPaymentTimestamp2;

        // 1666491497
        await setNextBlockTimestamp(
          lastPaymentTimestamp.add(getDaysInSeconds(30).add(1)) // late by 1 second
        );

        console.log(
          "latest block timestamp: ",
          (await getLatestBlockTimestamp()).toString()
        );

        await defaultStateManager.assessStates();
      });

      it("...should lock capital for 1st lending pool in protection pool 1", async () => {
        // Verify that 1st lending pool has locked capital instance
        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);

        expect(lockedCapitalsLendingPool1.length).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].snapshotId).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].amount).to.eq(0);
        expect(lockedCapitalsLendingPool1[0].locked).to.eq(true);
      });

      it("...should NOT lock capital for 2nd lending pool in protection pool 1", async () => {
        // Verify that 2nd lending pool has NO locked capital instance because it is in LateWithinGracePeriod state
        const lockedCapitalsLendingPool2 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[1]);

        expect(lockedCapitalsLendingPool2.length).to.eq(0);
      });

      it("...should lock capital for 2nd lending pool in protection pool 1", async () => {
        // Move time forward by 1 day + 1 second last payment timestamp
        // 2nd lending pool should mover from LateWithinGracePeriod to Late state
        await moveForwardTimeByDays(1);
        await defaultStateManager.assessStates();

        // Verify that 2nd lending pool in Pool 1 is in late state and has locked capital instances
        const lockedCapitalsLendingPool2 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[1]);

        expect(lockedCapitalsLendingPool2.length).to.eq(1);
        expect(lockedCapitalsLendingPool2[0].snapshotId).to.eq(2);

        // locked capital amount should be same as total protection bought from lending pool 2
        expect(lockedCapitalsLendingPool2[0].amount).to.eq(parseUSDC("20000"));
        expect(lockedCapitalsLendingPool2[0].locked).to.eq(true);
      });
    });

    describe("state transition from late -> active", async () => {
      before(async () => {
        // payment to lending pool
        await payToLendingPool(lendingPool2, "100000", usdcContract);

        await expect(defaultStateManager.assessStates())
          .to.emit(defaultStateManager, "PoolStatesAssessed")
          .to.emit(defaultStateManager, "LendingPoolUnlocked");
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

        it("...should return 10K claimable amount for seller from pool 1", async () => {
          // seller should be able claim 50% of the locked capital = 10K (50% of 20K)
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              sellerAddress
            )
          ).to.be.eq(parseUSDC("10000"));
        });

        it("...should return 10K claimable amount for account 1 from pool 1", async () => {
          // Account 1 should be able claim 50% of the locked capital = 10K (50% of 20K)
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              await account1.getAddress()
            )
          ).to.be.eq(parseUSDC("10000"));
        });
      });

      describe("calculateAndClaimUnlockedCapital", async () => {
        it("...should revert when called from non-pool address", async () => {
          await expect(
            defaultStateManager
              .connect(deployer)
              .calculateAndClaimUnlockedCapital(sellerAddress)
          ).to.be.revertedWith(
            `PoolNotRegistered("${await deployer.getAddress()}")`
          );
        });
      });
    });
  });
};

export { testDefaultStateManager };
