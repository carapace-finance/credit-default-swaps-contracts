import { DefaultStateManager } from "../../typechain-types/contracts/core/DefaultStateManager";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ZERO_ADDRESS } from "../utils/constants";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { PoolFactory } from "../../typechain-types/contracts/core/PoolFactory";
import { ethers } from "hardhat";
import { parseUSDC, getUsdcContract } from "../utils/usdc";
import {
  getUnixTimestampAheadByDays,
  moveForwardTimeByDays
} from "../utils/time";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";
import { payToLendingPool } from "../utils/goldfinch";
import { BigNumber } from "@ethersproject/bignumber";
import { getGoldfinchLender1 } from "../utils/goldfinch";

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

    before(async () => {
      lendingPool2 = (await ethers.getContractAt(
        "ITranchedPool",
        lendingPools[1]
      )) as ITranchedPool;

      usdcContract = getUsdcContract(deployer);
      pool1 = poolInstance.address;
      pool2 = await poolFactory.getPoolAddress(2);
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
        await usdcContract
          .connect(_account)
          .approve(poolInstance.address, _depositAmount);
        await poolInstance
          .connect(_account)
          .deposit(_depositAmount, _accountAddress);
      };

      before(async () => {
        // deposit capital into pool
        await depositToPool(seller, parseUSDC("5000"));
        await depositToPool(account1, parseUSDC("5000"));

        expect(await poolInstance.totalSTokenUnderlying()).to.equal(
          parseUSDC("10000")
        );

        // Buy protection
        const _protection_buyer = await getGoldfinchLender1();
        await usdcContract
          .connect(_protection_buyer)
          .approve(poolInstance.address, parseUSDC("3000"));
        await poolInstance.connect(_protection_buyer).buyProtection({
          lendingPoolAddress: lendingPools[1],
          nftLpTokenId: 590,
          protectionAmount: parseUSDC("20000"),
          protectionExpirationTimestamp: await getUnixTimestampAheadByDays(20)
        });
      });

      it("...should lock capital for both lending pools in pool 1", async () => {
        await moveForwardTimeByDays(30);
        await defaultStateManager.assessStates();

        // Verify that both lending pools in Pool 1 are in late state and has locked capital instances
        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);

        console.log("lockedCapitalsLendingPool1", lockedCapitalsLendingPool1);

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

        it("...should return 5000 claimable amount for seller from pool 1", async () => {
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              sellerAddress
            )
          ).to.be.eq(parseUSDC("5000"));
        });

        it("...should return 5000 claimable amount for account 1 from pool 1", async () => {
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              await account1.getAddress()
            )
          ).to.be.eq(parseUSDC("5000"));
        });
      });

      describe("calculateAndClaimUnlockedCapital", async () => {
        it("...should revert when called from non-pool address", async () => {
          await expect(
            defaultStateManager.calculateAndClaimUnlockedCapital(sellerAddress)
          ).to.be.revertedWith(
            `PoolNotRegistered("0x71b09d2eD6Bd3eC16e7a44c2afb1F111878Ea97E")`
          );
        });
      });
    });
  });
};

export { testDefaultStateManager };
