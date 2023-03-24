import { DefaultStateManager } from "../../typechain-types/contracts/core/DefaultStateManager";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ZERO_ADDRESS, OPERATOR_ROLE } from "../utils/constants";
import { ProtectionPool } from "../../typechain-types/contracts/core/pool/ProtectionPool";
import { ContractFactory as CPContractFactory } from "../../typechain-types/contracts/core/ContractFactory";
import { ethers, upgrades } from "hardhat";
import { parseEther } from "ethers/lib/utils";
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
import { payToLendingPool, payToLendingPoolAddress } from "../utils/goldfinch";
import { BigNumber } from "@ethersproject/bignumber";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { DefaultStateManagerV2 } from "../../typechain-types/contracts/test/DefaultStateManagerV2";
import { cpContractFactoryInstance, protectionPoolInstance } from "../../utils/deploy";
import { LATE_PAYMENT_GRACE_PERIOD_IN_DAYS } from "../../scripts/local-mainnet/data";

const testDefaultStateManager: Function = (
  deployer: Signer,
  account1: Signer,
  seller: Signer,
  operator: Signer,
  defaultStateManager: DefaultStateManager,
  contractFactory: CPContractFactory,
  poolInstance: ProtectionPool,
  lendingPools: string[]
) => {
  describe("DefaultStateManager", () => {
    let usdcContract: Contract;
    let lendingPool2: ITranchedPool;
    let pool1: string;
    let pool2: string;
    let sellerAddress: string;
    let referenceLendingPoolsInstance: ReferenceLendingPools;

    const verifyLendingPoolHasLockedCapital = async (
      protectionPool: string,
      lendingPool: string,
      status: number,
      snapshotId: number,
      lockedAmount: string
    ) => {
      // Verify that the lending pool in protection pool is in specified status
      expect(
        await defaultStateManager.getLendingPoolStatus(
          protectionPool,
          lendingPool
        )
      ).to.eq(status);

      // Verify that the lending pool in protection pool has locked capital
      const lockedCapitalsLendingPool =
        await defaultStateManager.getLockedCapitals(
          protectionPool,
          lendingPool
        );

      expect(lockedCapitalsLendingPool.length).to.eq(1);
      expect(lockedCapitalsLendingPool[0].snapshotId).to.eq(snapshotId);

      // locked capital amount should be same as total protection bought from lending pool 2
      expect(lockedCapitalsLendingPool[0].amount).to.eq(
        parseUSDC(lockedAmount)
      );
      expect(lockedCapitalsLendingPool[0].locked).to.eq(true);
    };

    before(async () => {
      lendingPool2 = (await ethers.getContractAt(
        "ITranchedPool",
        lendingPools[1]
      )) as ITranchedPool;

      usdcContract = getUsdcContract(deployer);
      pool1 = poolInstance.address;
      pool2 = (await contractFactory.getProtectionPools())[1];
      sellerAddress = await seller.getAddress();

      referenceLendingPoolsInstance = (await ethers.getContractAt(
        "ReferenceLendingPools",
        (
          await poolInstance.getPoolInfo()
        ).referenceLendingPools
      )) as ReferenceLendingPools;
    });

    describe("implementation", async () => {
      let defaultStateManagerImplementation: DefaultStateManager;

      before(async () => {
        defaultStateManagerImplementation = (await ethers.getContractAt(
          "DefaultStateManager",
          await upgrades.erc1967.getImplementationAddress(
            defaultStateManager.address
          )
        )) as DefaultStateManager;
      });

      it("...should NOT have an owner on construction", async () => {
        expect(await defaultStateManagerImplementation.owner()).to.equal(
          ZERO_ADDRESS
        );
      });

      it("...should disable initialize after construction", async () => {
        await expect(
          defaultStateManagerImplementation.initialize(ZERO_ADDRESS)
        ).to.be.revertedWith("Initializable: contract is already initialized");
      });
    });

    describe("constructor", async () => {
      it("...should be valid instance", async () => {
        expect(defaultStateManager).to.not.equal(undefined);
      });

      it("...should set deployer as on owner", async () => {
        expect(await defaultStateManager.owner()).to.equal(
          await deployer.getAddress()
        );
      });

      it("... should revert when initialize is called 2nd time", async () => {
        await expect(defaultStateManager.initialize(ZERO_ADDRESS)).to.be.revertedWith(
          "Initializable: contract is already initialized"
        );
      });

      it("...should have dummy pool state at index 0", async () => {
        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(ZERO_ADDRESS)
        ).to.equal(0);
      });
    });

    describe("registerProtectionPool", async () => {
      it("...should NOT be callable by non-pool-factory address", async () => {
        await expect(
          defaultStateManager
            .connect(account1)
            .registerProtectionPool(ZERO_ADDRESS)
        ).to.be.revertedWith(
          `NotContractFactory("${await account1.getAddress()}")`
        );
      });

      it("...should fail to register already registered pool", async () => {
        await defaultStateManager
          .connect(deployer)
          .setContractFactory(await account1.getAddress());

        await expect(
          defaultStateManager
            .connect(account1)
            .registerProtectionPool(poolInstance.address)
        ).to.be.revertedWith(
          `PoolAlreadyRegistered("${await poolInstance.address}")`
        );
      });

      it("...sets contractFactory address back to contract factory address", async () => {
        await defaultStateManager
          .connect(deployer)
          .setContractFactory(cpContractFactoryInstance.address);
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

    describe("setContractFactory", async () => {
      it("...should fail when called by non-owner", async () => {
        await expect(
          defaultStateManager.connect(account1).setContractFactory(ZERO_ADDRESS)
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...should fail when address is zero", async () => {
        await expect(
          defaultStateManager.connect(deployer).setContractFactory(ZERO_ADDRESS)
        ).to.be.revertedWith("ZeroContractFactoryAddress");
      });

      it("...should work correctly by owner", async () => {
        expect(await defaultStateManager.contractFactoryAddress()).to.equal(
          cpContractFactoryInstance.address
        );

        await expect(
          defaultStateManager
            .connect(deployer)
            .setContractFactory(await account1.getAddress())
        ).to.emit(defaultStateManager, "ContractFactoryUpdated");

        expect(await defaultStateManager.contractFactoryAddress()).to.equal(
          await account1.getAddress()
        );
      });
    });

    describe("getLendingPoolStatus", async () => {
      it("...should return NotSupported status for non-registered pool", async () => {
        expect(
          await defaultStateManager.getLendingPoolStatus(lendingPools[0], pool1)
        ).to.equal(0);
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
        // We are at day 11 of pool cycle 1 because of revert after ProtectionPool tests

        // Make lending pool 1 and 2 active
        await payToLendingPoolAddress(lendingPools[0], "300000", usdcContract);
        await payToLendingPoolAddress(lendingPools[1], "300000", usdcContract);

        let protectionBuyer = await ethers.getImpersonatedSigner(
          "0x5CD8C821C080b7340df6969252a979Ed416a4e3F"
        );
        let _expectedPremiumAmt = parseUSDC("10000");
        await usdcContract
          .connect(protectionBuyer)
          .approve(protectionPoolInstance.address, _expectedPremiumAmt);

        await protectionPoolInstance.connect(protectionBuyer).buyProtection(
          {
            lendingPoolAddress: lendingPools[1],
            nftLpTokenId: 579,
            protectionAmount: parseUSDC("50000"),
            protectionDurationInSeconds: getDaysInSeconds(35)
          },
          _expectedPremiumAmt
        );

        // State of the pool 1 after pool tests
        // 100K protection in lending pool 2: 0xd09a57127bc40d680be7cb061c2a6629fe71abef
        // total sToken underlying = 100,200
        // total protection: 100,000
        const [_totalSTokenUnderlying, _totalProtection] =
          await poolInstance.getPoolDetails();
        
        // total sToken underlying should be > 100,200 because of accrued premium
        expect(_totalSTokenUnderlying).to.be.gt(parseUSDC("100200"));
        expect(_totalProtection).to.equal(parseUSDC("100000"));

        // deposit capital into pool
        await protectionPoolInstance.updateLeverageRatioParams(
          parseEther("0.5"),
          parseEther("2"),
          parseEther("0.05")
        );
        await depositToPool(seller, parseUSDC("59800"));
        
        // totalSTokenUnderlying = 100,200 + 59,800 + accrued premium should be > 160,000
        expect((await poolInstance.getPoolDetails())[0]).to.be.gt(
          parseUSDC("160000")
        );

        // Pool should be in Open phase
        expect((await poolInstance.getPoolInfo()).currentPhase).to.eq(2);

        await defaultStateManager.connect(operator).assessStateBatch([pool1]);

        // verify that both lending pools are active
        for (let i = 0; i < 2; i++) {
          expect(
            await defaultStateManager.getLendingPoolStatus(
              pool1,
              lendingPools[i]
            )
          ).to.eq(1);
        }

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

        await defaultStateManager.connect(operator).assessStateBatch([pool1]);

        // accrue premium and expire protections
        await protectionPoolInstance
          .connect(operator)
          .accruePremiumAndExpireProtections([]);
      });

      it("...should NOT lock capital for 1st & 2nd lending pools in protection pool 1", async () => {
        // iterate 1st two lending pools
        for (let i = 0; i < 2; i++) {
          expect(
            await defaultStateManager.getLendingPoolStatus(
              pool1,
              lendingPools[i]
            )
          ).to.eq(2); // LateWithinGracePeriod

          // Verify that 1st & 2nd lending pools have NO locked capital instance because it is in LateWithinGracePeriod state
          const lockedCapitalsLendingPool =
            await defaultStateManager.getLockedCapitals(pool1, lendingPools[i]);
          expect(lockedCapitalsLendingPool.length).to.eq(0);
        }
      });

      it("...should mark 1st & 2nd lending pools as Late in protection pool 1", async () => {
        // Move time forward by LATE_PAYMENT_GRACE_PERIOD_IN_DAYS day + 1 second last payment timestamp
        await moveForwardTimeByDays(LATE_PAYMENT_GRACE_PERIOD_IN_DAYS);
        for (let i = 0; i < 2; i++) {
          await defaultStateManager.connect(operator).assessStateBatch([pool1]);

          // both lending pools should move from LateWithinGracePeriod to Late state
          expect(
            await defaultStateManager.getLendingPoolStatus(
              pool1,
              lendingPools[i]
            )
          ).to.eq(3); // Late
        }
      });

      it("...should lock capital for 1st lending pool in protection pool 1", async () => {
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[0])
        ).to.eq(3);

        // Verify that 1st lending pool has locked capital instance because it is in Late state
        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);

        expect(lockedCapitalsLendingPool1.length).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].snapshotId).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].amount).to.eq(parseUSDC("0"));
        expect(lockedCapitalsLendingPool1[0].locked).to.eq(true);
      });
      
      it("...should lock capital for 2nd lending pool in protection pool 1", async () => {
        // 2nd lending pool should move from LateWithinGracePeriod to Late state with a locked capital instance
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[1])
        ).to.eq(3); // Late

        const lockedCapitalsLendingPool2 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[1]);
        expect(lockedCapitalsLendingPool2.length).to.eq(1);
        expect(lockedCapitalsLendingPool2[0].snapshotId).to.eq(2);

        // locked capital amount should be same as total protection bought from lending pool 2
        expect(lockedCapitalsLendingPool2[0].amount).to.eq(parseUSDC("50000"));
        expect(lockedCapitalsLendingPool2[0].locked).to.eq(true);
      });
    });

    describe("state transition from late -> active or default", async () => {
      before(async () => {
        // Make 2 payments to 2nd lending pool and no payment to 1st lending pool
        for (let i = 0; i < 2; i++) {
          await moveForwardTimeByDays(30);
          await payToLendingPool(lendingPool2, "300000", usdcContract);

          if (i === 0) {
            await defaultStateManager.connect(operator).assessStateBatch([pool1]);
          } else {
            // after second payment, 2nd lending pool should move from Late to Active state
            await expect(
              defaultStateManager.connect(operator).assessStateBatch([pool1])
            )
              .to.emit(defaultStateManager, "ProtectionPoolStatesAssessed")
              .to.emit(defaultStateManager, "LendingPoolUnlocked");
          }
        }
      });

      it("...1st lending pool in protection pool 1 should be in default state with locked capital", async () => {
        // 1st lending pool should move from Late to Default state with locked capital instances
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[0])
        ).to.eq(4); // Default

        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);
        expect(lockedCapitalsLendingPool1.length).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].snapshotId).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].amount).to.eq(parseUSDC("0"));
        expect(lockedCapitalsLendingPool1[0].locked).to.eq(true);
      });

      const calculateClaimableAmt = async (accountAddress: string, lockedAmount: string) => { 
        return (await protectionPoolInstance.balanceOf(accountAddress))
          .mul(parseUSDC(lockedAmount))
          .div(await protectionPoolInstance.totalSupply());
      };

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
          // Seller has deposited 80K USDC out of 160k total capital,
          // so seller should be able claim ~1/2 of the locked capital = ~25K (50% of 50K)
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              sellerAddress
            )
          ).to.be.eq(await calculateClaimableAmt(sellerAddress, "50000"));
        });

        it("...should return correct claimable amount for account 1 from pool 1", async () => {
          // Account1 has deposited 40K USDC out of 160k total capital,
          // so account1 should be able claim ~1/4 of the locked capital = ~12.5K (25% of 50K)
          const account1Address = await account1.getAddress();
          
          expect(
            await defaultStateManager.calculateClaimableUnlockedAmount(
              pool1,
              account1Address
            )
          ).to.be.eq(await calculateClaimableAmt(account1Address, "50000"));
        });

        // This unit tests needs to be reworked because of the protections being expired in the lockCapital function
        xdescribe("multiple locked capital instances", async () => { 
          before(async () => {
            // Remaining capital in pool should be 40K USDC because 120K USDC is locked
            const _totalSTokenUnderlying = (
              await protectionPoolInstance.getPoolDetails()
            )[0];
            /// out of 160K deposit, 50K is locked, so 113K is available because of accrued premium
            expect(_totalSTokenUnderlying)
              .to.gt(parseUSDC("113368"))
              .and.to.lt(parseUSDC("113369"));

            expect(
              await defaultStateManager.getLendingPoolStatus(
                pool1,
                lendingPools[1]
              )
            ).to.eq(1); // Active

            await protectionPoolInstance
              .connect(operator)
              .accruePremiumAndExpireProtections([]);

            // Move time forward by 31 days and make no payment to 2nd lending pool
            await moveForwardTimeByDays(31);

            // 2nd lending pool should move from Active to Late state
            await expect(
              defaultStateManager.connect(operator).assessStateBatch([pool1])
            )
              .to.emit(defaultStateManager, "ProtectionPoolStatesAssessed")
              .to.emit(defaultStateManager, "LendingPoolLocked");
          });

          it("...should create 2nd lock capital instance for 2nd lending pool in protection pool 1", async () => {
            // 2nd lending pool should move from LateWithinGracePeriod to Late state with a locked capital instance
            expect(
              await defaultStateManager.getLendingPoolStatus(
                pool1,
                lendingPools[1]
              )
            ).to.eq(3); // Late

            const lockedCapitalsLendingPool2 =
              await defaultStateManager.getLockedCapitals(
                pool1,
                lendingPools[1]
              );
            expect(lockedCapitalsLendingPool2.length).to.eq(2);
            expect(lockedCapitalsLendingPool2[1].snapshotId).to.eq(3);

            // locked capital amount should be same as total protection bought from lending pool 2,
            // but total capital remaining is 40K USDC, so 40K will be locked
            expect(lockedCapitalsLendingPool2[1].amount).to.eq(
              parseUSDC("40000")
            );
            expect(lockedCapitalsLendingPool2[1].locked).to.eq(true);
          });

          it("...should return correct claimable amount from 1st locked capital instance for seller from pool 1", async () => {
            // so seller should be able claim 1/2 of the 1st unlocked capital = 25K (50% of 50K)
            // 2nd locked capital is not unlocked yet
            expect(
              await defaultStateManager.calculateClaimableUnlockedAmount(
                pool1,
                sellerAddress
              )
            ).to.be.eq(await calculateClaimableAmt(sellerAddress, "50000"));
          });

          it("...should move 2nd lending pool from Late to Active state", async () => {
            // Move 2nd lending pool from Late o Active state
            for (let i = 0; i < 2; i++) {
              await moveForwardTimeByDays(30);
              await payToLendingPool(lendingPool2, "300000", usdcContract);

              if (i === 0) {
                await defaultStateManager
                  .connect(operator)
                  .assessStateBatch([pool1]);
              } else {
                // after second payment, 2nd lending pool should move from Late to Active state
                await expect(defaultStateManager.assessStateBatch([pool1]))
                  .to.emit(defaultStateManager, "ProtectionPoolStatesAssessed")
                  .to.emit(defaultStateManager, "LendingPoolUnlocked");
              }
            }

            expect(
              await defaultStateManager.getLendingPoolStatus(
                pool1,
                lendingPools[1]
              )
            ).to.eq(1); // Active
          });
          
          it("...should return correct claimable amount from 2 locked capital instances for seller from pool 1", async () => {
            // so seller should be able claim 1/2 of the 1st unlocked capital = 25K (50% of 50K)
            // so seller should be able claim 1/2 of the 2nd unlocked capital = 20K (50% of 40K)
            expect(
              await defaultStateManager.calculateClaimableUnlockedAmount(
                pool1,
                sellerAddress
              )
            ).to.be.eq(parseUSDC("45000")); // 25K + 20K
          });
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

    describe("state transition from active -> late -> default", async () => {
      before(async () => {
        // verify the current status of both lending pools
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[0])
        ).to.eq(4); // default
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[1])
        ).to.eq(1); // active

        // Move time forward by 30 days
        await moveForwardTimeByDays(31);

        console.log(
          "Assessing states at time: ",
          await getLatestBlockTimestamp()
        );

        await expect(
          defaultStateManager.connect(operator).assessStateBatch([pool1])
        )
          .to.emit(defaultStateManager, "ProtectionPoolStatesAssessed")
          .to.not.emit(defaultStateManager, "LendingPoolUnlocked");
      });

      it("...1st lending pool in protection pool 1 should still be in default state with locked capital", async () => {
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[0])
        ).to.eq(4); // Default

        const lockedCapitalsLendingPool1 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[0]);
        expect(lockedCapitalsLendingPool1.length).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].snapshotId).to.eq(1);
        expect(lockedCapitalsLendingPool1[0].amount).to.eq(parseUSDC("0"));
        expect(lockedCapitalsLendingPool1[0].locked).to.eq(true);
      });

      it("...2nd lending pool in protection pool 1 should be in late state with locked capital", async () => {
        // after 1 missed payment, 2nd lending pool should move from Active to Late state
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[1])
        ).to.eq(3); // Late

        // 2nd lending pool should have 2 locked capital instances at this point
        const lockedCapitalsLendingPool2 =
          await defaultStateManager.getLockedCapitals(pool1, lendingPools[1]);
        expect(lockedCapitalsLendingPool2.length).to.eq(2);
        expect(lockedCapitalsLendingPool2[1].snapshotId).to.eq(3);

        // locked capital amount should be 0 as protection pool has no capital left to lock
        expect(lockedCapitalsLendingPool2[1].amount).to.eq(0);
        expect(lockedCapitalsLendingPool2[1].locked).to.eq(true);
      });

      it("...2nd lending pool in protection pool 1 should be in default state with locked capital", async () => {
        // Move time forward by 60 days (2 payment periods)
        await moveForwardTimeByDays(60);

        // after 2 missed payments, 2nd lending pool should move from Late to Default state
        await expect(
          defaultStateManager.connect(operator).assessStateBatch([pool1])
        )
          .to.emit(defaultStateManager, "ProtectionPoolStatesAssessed")
          .to.not.emit(defaultStateManager, "LendingPoolUnlocked");

        // after 2 missed payments, 2nd lending pool should move from Late to Defaulted state
        expect(
          await defaultStateManager.getLendingPoolStatus(pool1, lendingPools[1])
        ).to.eq(4); // Default
      });
    });

    // TODO: Discuss with goldfinch team
    // Why does lending pool not accept large payments?
    xdescribe("Active -> Expired", async () => {
      before(async () => {
        // pay 10M to 2nd lending pool to move it to Expired state
        await moveForwardTimeByDays(30);
        await payToLendingPoolAddress(lendingPools[1], "3000000", usdcContract);

        await defaultStateManager.connect(operator).assessStateBatch([pool1]);
      });

      it("...lending pool 2 should be in Expired state", async () => {
        expect(
          await defaultStateManager.getLendingPoolStatus(
            pool1,
            lendingPool2.address
          )
        ).to.eq(5);
      });
    });

    describe("assessStates", async () => {
      it("...should fail when called by non-operator", async () => {
        await expect(
          defaultStateManager.connect(seller).assessStates()
        ).to.be.revertedWith(
          `AccessControl: account ${sellerAddress.toLowerCase()} is missing role ${OPERATOR_ROLE}`
        );
      });

      it("...should update states for registered pools", async () => {
        const pool1UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1);
        const pool2UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2);

        await expect(defaultStateManager.connect(operator).assessStates()).to.emit(
          defaultStateManager,
          "ProtectionPoolStatesAssessed"
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
      it("...should fail when called by non-operator", async () => {
        await expect(
          defaultStateManager.connect(seller).assessStateBatch([pool1])
        ).to.be.revertedWith(
          `AccessControl: account ${sellerAddress.toLowerCase()} is missing role ${OPERATOR_ROLE}`
        );
      });
      it("...should update state for specified registered pool", async () => {
        const pool1UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1);
        const pool2UpdateTimestamp =
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2);

        await defaultStateManager.connect(operator).assessStateBatch([pool1]);
        await defaultStateManager.connect(operator).assessStateBatch([pool2]);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool1)
        ).to.be.gt(pool1UpdateTimestamp);

        expect(
          await defaultStateManager.getPoolStateUpdateTimestamp(pool2)
        ).to.be.gt(pool2UpdateTimestamp);
      });
    });

    describe("upgrade", () => {
      let upgradedDefaultStateManager: DefaultStateManagerV2;

      it("... should revert when upgradeTo is called by non-owner", async () => {
        await expect(
          defaultStateManager
            .connect(account1)
            .upgradeTo("0xA18173d6cf19e4Cc5a7F63780Fe4738b12E8b781")
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("... should fail upon invalid upgrade", async () => {
        try {
          await upgrades.validateUpgrade(
            defaultStateManager.address,
            await ethers.getContractFactory(
              "DefaultStateManagerV2NotUpgradable"
            ),
            {
              kind: "uups"
            }
          );
        } catch (e: any) {
          expect(e.message).includes(
            "Contract `contracts/test/DefaultStateManagerV2.sol:DefaultStateManagerV2NotUpgradable` is not upgrade safe"
          );
        }
      });

      it("... should upgrade successfully", async () => {
        const defaultStateManagerV2Factory = await ethers.getContractFactory(
          "DefaultStateManagerV2"
        );

        // upgrade to v2
        upgradedDefaultStateManager = (await upgrades.upgradeProxy(
          defaultStateManager.address,
          defaultStateManagerV2Factory
        )) as DefaultStateManagerV2;
      });

      it("... should have same address after upgrade", async () => {
        expect(upgradedDefaultStateManager.address).to.be.equal(
          defaultStateManager.address
        );
      });

      it("... should be able to call new function in v2", async () => {
        const value = await upgradedDefaultStateManager.getVersion();
        expect(value).to.equal("v2");
      });

      it("... should be able to call existing function in v1", async () => {
        await expect(
          upgradedDefaultStateManager.connect(operator).assessStates()
        ).to.emit(upgradedDefaultStateManager, "ProtectionPoolStatesAssessed");
      });
    });

    after(async () => {
      defaultStateManager
        .connect(deployer)
        .setContractFactory(cpContractFactoryInstance.address);
    });
  });
};

export { testDefaultStateManager };

