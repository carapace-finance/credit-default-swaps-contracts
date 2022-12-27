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
  moveForwardTimeByDays,
  setNextBlockTimestamp
} from "../utils/time";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";
import { payToLendingPool, payToLendingPoolAddress } from "../utils/goldfinch";
import { BigNumber } from "@ethersproject/bignumber";
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
        // State of the pool 1 after pool tests
        // 70K protection in lending pool 3: 0xb26B42Dd5771689D0a7faEea32825ff9710b9c11
        // 50K protection in lending pool 3: 0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf
        // total sToken underlying = 100,200
        // total protection: 120,000
        expect(await poolInstance.totalSTokenUnderlying()).to.equal(
          parseUSDC("100200")
        );

        expect(await poolInstance.totalProtection()).to.equal(
          parseUSDC("120000")
        );

        // deposit capital into pool
        await depositToPool(seller, parseUSDC("19800"));

        // Pool should be in Open phase
        expect((await poolInstance.getPoolInfo()).currentPhase).to.eq(2);

        // Make lending pool 1 and 2 active
        await payToLendingPoolAddress(lendingPools[0], "300000", usdcContract);
        await payToLendingPoolAddress(lendingPools[1], "300000", usdcContract);

        await defaultStateManager.assessStates();

        // Move time forward by 30 days from last payment timestamp
        const lastPaymentTimestamp1 =
          await referenceLendingPoolsInstance.getLatestPaymentTimestamp(
            lendingPools[0]
          );

        const lastPaymentTimestamp2 =
          await referenceLendingPoolsInstance.getLatestPaymentTimestamp(
            lendingPools[1]
          );

        const lastPaymentTimestamp = lastPaymentTimestamp1.gt(
          lastPaymentTimestamp2
        )
          ? lastPaymentTimestamp1
          : lastPaymentTimestamp2;

        await setNextBlockTimestamp(
          lastPaymentTimestamp.add(getDaysInSeconds(30).add(1)) // late by 1 second
        );

        await defaultStateManager.assessStates();
      });

      it("...should lock capital for 1st lending pool in protection pool 1", async () => {
        // Verify that 1st lending pool has locked capital instance because it is in Late state
        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);

        expect(lockedCapitalsLendingPool1.length).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].snapshotId).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].amount).to.eq(parseUSDC("70000"));
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
        expect(lockedCapitalsLendingPool2[0].amount).to.eq(parseUSDC("50000"));
        expect(lockedCapitalsLendingPool2[0].locked).to.eq(true);
      });
    });

    describe("state transition from late -> active", async () => {
      before(async () => {
        // Make 2 consecutive payments to 2nd lending pool
        for (let i = 0; i < 2; i++) {
          await moveForwardTimeByDays(30);
          await payToLendingPool(lendingPool2, "300000", usdcContract);

          if (i === 0) {
            await defaultStateManager.assessStates();
          } else {
            // after second payment, 2nd lending pool should move from Late to Active state
            await expect(defaultStateManager.assessStates())
              .to.emit(defaultStateManager, "PoolStatesAssessed")
              .to.emit(defaultStateManager, "LendingPoolUnlocked");
          }
        }
      });

      it("...1st lending pool in protection pool 1 should stay locked", async () => {
        // Verify that 1st lending pool is still locked
        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);

        expect(lockedCapitalsLendingPool1.length).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].snapshotId).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].amount).to.eq(parseUSDC("70000"));
        expect(lockedCapitalsLendingPool1[0].locked).to.eq(true);
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

        it("...should return correct claimable amount for seller from pool 1", async () => {
          // seller should be able claim 1/3rd of the locked capital = 16.66K (33.33% of 50K)
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              sellerAddress
            )
          ).to.be.eq(parseUSDC("16666.666666"));
        });

        it("...should return correct claimable amount for account 1 from pool 1", async () => {
          // Account 1 should be able claim 1/3rd of the locked capital = 16.66K (33.33% of 50K)
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              await account1.getAddress()
            )
          ).to.be.eq(parseUSDC("16666.666666"));
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
  });
};

export { testDefaultStateManager };
