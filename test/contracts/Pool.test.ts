import { BigNumber } from "@ethersproject/bignumber";
import { expect, should } from "chai";
import { Contract, Signer } from "ethers";
import { ethers, network } from "hardhat";
import { parseEther } from "ethers/lib/utils";
import {
  Pool,
  ProtectionInfoStructOutput
} from "../../typechain-types/contracts/core/pool/Pool";
import { PoolInfoStructOutput } from "../../typechain-types/contracts/interfaces/IPool";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ProtectionPurchaseParamsStruct } from "../../typechain-types/contracts/interfaces/IReferenceLendingPools";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import {
  getDaysInSeconds,
  getLatestBlockTimestamp,
  getUnixTimestampAheadByDays,
  moveForwardTimeByDays,
  setNextBlockTimestamp
} from "../utils/time";
import {
  parseUSDC,
  getUsdcContract,
  impersonateCircle,
  formatUSDC,
  transferAndApproveUsdc
} from "../utils/usdc";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";
import { payToLendingPool, payToLendingPoolAddress } from "../utils/goldfinch";
import { DefaultStateManager } from "../../typechain-types/contracts/core/DefaultStateManager";
import { poolInstance } from "../../utils/deploy";
import { ZERO_ADDRESS } from "../utils/constants";
import { getGoldfinchLender1 } from "../utils/goldfinch";

const testPool: Function = (
  deployer: Signer,
  owner: Signer,
  buyer: Signer,
  seller: Signer,
  account4: Signer,
  pool: Pool,
  referenceLendingPools: ReferenceLendingPools,
  poolCycleManager: PoolCycleManager,
  defaultStateManager: DefaultStateManager
) => {
  describe("Pool", () => {
    const PROTECTION_BUYER1_ADDRESS =
      "0x008c84421da5527f462886cec43d2717b686a7e4";

    const _newFloor: BigNumber = BigNumber.from(100);
    const _newCeiling: BigNumber = BigNumber.from(500);
    let deployerAddress: string;
    let sellerAddress: string;
    let account4Address: string;
    let buyerAddress: string;
    let ownerAddress: string;
    let USDC: Contract;
    let poolInfo: PoolInfoStructOutput;
    let before1stDepositSnapshotId: string;
    let snapshotId2: string;
    let _protectionBuyer1: Signer;
    let _protectionBuyer2: Signer;
    let _protectionBuyer3: Signer;
    let _protectionBuyer4: Signer;
    let _circleAccount: Signer;
    let _goldfinchLendingPools: string[];
    let _lendingPool1: string;
    let _lendingPool2: string;

    const calculateTotalSellerDeposit = async () => {
      // seller deposit should total sToken underlying - premium accrued
      return (await pool.totalSTokenUnderlying()).sub(
        await pool.totalPremiumAccrued()
      );
    };

    const depositAndRequestWithdrawal = async (
      _account: Signer,
      _accountAddress: string,
      _depositAmount: BigNumber,
      _withdrawalAmount: BigNumber
    ) => {
      await USDC.connect(_account).approve(pool.address, _depositAmount);
      await pool.connect(_account).deposit(_depositAmount, _accountAddress);
      await pool.connect(_account).requestWithdrawal(_withdrawalAmount);
    };

    const verifyWithdrawal = async (
      _account: Signer,
      _sTokenWithdrawalAmt: BigNumber
    ) => {
      const accountAddress = await _account.getAddress();
      const sTokenBalanceBefore = await pool.balanceOf(accountAddress);
      const usdcBalanceBefore = await USDC.balanceOf(accountAddress);
      const poolUsdcBalanceBefore = await USDC.balanceOf(pool.address);
      const poolTotalSTokenUnderlyingBefore =
        await pool.totalSTokenUnderlying();

      const expectedUsdcWithdrawalAmt = await pool.convertToUnderlying(
        _sTokenWithdrawalAmt
      );

      // withdraw sTokens
      await expect(
        pool.connect(_account).withdraw(_sTokenWithdrawalAmt, accountAddress)
      )
        .to.emit(pool, "WithdrawalMade")
        .withArgs(accountAddress, _sTokenWithdrawalAmt, accountAddress);

      const sTokenBalanceAfter = await pool.balanceOf(accountAddress);
      expect(sTokenBalanceBefore.sub(sTokenBalanceAfter)).to.eq(
        _sTokenWithdrawalAmt
      );

      const usdcBalanceAfter = await USDC.balanceOf(accountAddress);
      expect(usdcBalanceAfter.sub(usdcBalanceBefore)).to.be.eq(
        expectedUsdcWithdrawalAmt
      );

      const poolUsdcBalanceAfter = await USDC.balanceOf(pool.address);
      expect(poolUsdcBalanceBefore.sub(poolUsdcBalanceAfter)).to.eq(
        expectedUsdcWithdrawalAmt
      );

      const poolTotalSTokenUnderlyingAfter = await pool.totalSTokenUnderlying();
      expect(
        poolTotalSTokenUnderlyingBefore.sub(poolTotalSTokenUnderlyingAfter)
      ).to.eq(expectedUsdcWithdrawalAmt);
    };

    const transferAndApproveUsdcToPool = async (
      _buyer: Signer,
      _amount: BigNumber
    ) => {
      await transferAndApproveUsdc(_buyer, _amount, pool.address);
    };

    const verifyPoolState = async (
      expectedCycleIndex: number,
      expectedState: number
    ) => {
      await poolCycleManager.calculateAndSetPoolCycleState(poolInfo.poolId);
      const currentPoolCycle = await poolCycleManager.getCurrentPoolCycle(
        poolInfo.poolId
      );
      expect(currentPoolCycle.currentCycleIndex).to.equal(expectedCycleIndex);
      expect(currentPoolCycle.currentCycleState).to.eq(expectedState);
    };

    const getActiveProtections = async () => {
      const allProtections = await pool.getAllProtections();
      return allProtections.filter((p: any) => p.expired === false);
    };

    const depositAndVerify = async (
      _account: Signer,
      _depositAmount: string
    ) => {
      const _underlyingAmount: BigNumber = parseUSDC(_depositAmount);
      const _accountAddress = await _account.getAddress();
      let _totalSTokenUnderlyingBefore = await pool.totalSTokenUnderlying();
      let _poolUsdcBalanceBefore = await USDC.balanceOf(pool.address);
      let _sTokenBalanceBefore = await pool.balanceOf(_accountAddress);

      await transferAndApproveUsdcToPool(_account, _underlyingAmount);
      await expect(
        pool.connect(_account).deposit(_underlyingAmount, _accountAddress)
      )
        .to.emit(pool, "ProtectionSold")
        .withArgs(_accountAddress, _underlyingAmount);

      // Seller should receive same sTokens shares as the deposit because of no premium accrued
      let _sTokenBalanceAfter = await pool.balanceOf(_accountAddress);
      const _sTokenReceived = _sTokenBalanceAfter.sub(_sTokenBalanceBefore);
      expect(_sTokenReceived).to.eq(parseEther(_depositAmount));

      // Verify the pool's total sToken underlying is updated correctly
      let _totalSTokenUnderlyingAfter = await pool.totalSTokenUnderlying();
      expect(
        _totalSTokenUnderlyingAfter.sub(_totalSTokenUnderlyingBefore)
      ).to.eq(_underlyingAmount);

      // Verify the pool's USDC balance is updated correctly
      let _poolUsdcBalanceAfter = await USDC.balanceOf(pool.address);
      expect(_poolUsdcBalanceAfter.sub(_poolUsdcBalanceBefore)).to.eq(
        _underlyingAmount
      );

      // Seller should receive same USDC amt as deposited because no premium accrued
      expect(await pool.convertToUnderlying(_sTokenReceived)).to.be.eq(
        _underlyingAmount
      );
    };

    const verifyMaxAllowedProtectionDuration = async () => {
      const currentTimestamp = await getLatestBlockTimestamp();
      const currentPoolCycle = await poolCycleManager.getCurrentPoolCycle(
        poolInfo.poolId
      );

      // max duration = next cycle's end timestamp - currentTimestamp
      expect(await poolInstance.calculateMaxAllowedProtectionDuration()).to.eq(
        currentPoolCycle.currentCycleStartTime
          .add(currentPoolCycle.cycleDuration.mul(2))
          .sub(currentTimestamp)
      );
    };

    before("setup", async () => {
      deployerAddress = await deployer.getAddress();
      sellerAddress = await seller.getAddress();
      buyerAddress = await buyer.getAddress();
      ownerAddress = await owner.getAddress();
      account4Address = await account4.getAddress();
      poolInfo = await pool.getPoolInfo();
      USDC = getUsdcContract(deployer);

      // Impersonate CIRCLE account and transfer some USDC to test accounts
      _circleAccount = await impersonateCircle();
      USDC.connect(_circleAccount).transfer(
        deployerAddress,
        parseUSDC("1000000")
      );
      USDC.connect(_circleAccount).transfer(ownerAddress, parseUSDC("20000"));
      USDC.connect(_circleAccount).transfer(sellerAddress, parseUSDC("20000"));
      USDC.connect(_circleAccount).transfer(
        account4Address,
        parseUSDC("20000")
      );

      // 420K principal for token 590
      _protectionBuyer1 = await getGoldfinchLender1();

      USDC.connect(_circleAccount).transfer(
        PROTECTION_BUYER1_ADDRESS,
        parseUSDC("1000000")
      );

      // these lending pools have been already added to referenceLendingPools instance
      // Lending pool details: https://app.goldfinch.finance/pools/0xd09a57127bc40d680be7cb061c2a6629fe71abef
      // Lending pool tokens: https://lark.market/?attributes%5BPool+Address%5D=0xd09a57127bc40d680be7cb061c2a6629fe71abef
      _goldfinchLendingPools = await referenceLendingPools.getLendingPools();
      _lendingPool1 = _goldfinchLendingPools[0];
      _lendingPool2 = _goldfinchLendingPools[1];
    });

    describe("constructor", () => {
      it("...set the SToken name", async () => {
        const _name: string = await pool.name();
        expect(_name).to.eq("sToken11");
      });

      it("...set the SToken symbol", async () => {
        const _symbol: string = await pool.symbol();
        expect(_symbol).to.eq("sT11");
      });

      it("...set the pool id", async () => {
        expect(poolInfo.poolId.toString()).to.eq("1");
      });

      it("...set the leverage ratio floor", async () => {
        expect(poolInfo.params.leverageRatioFloor).to.eq(parseEther("0.5"));
      });

      it("...set the leverage ratio ceiling", async () => {
        expect(poolInfo.params.leverageRatioCeiling).to.eq(parseEther("1"));
      });

      it("...set the leverage ratio buffer", async () => {
        expect(poolInfo.params.leverageRatioBuffer).to.eq(parseEther("0.05"));
      });

      it("...set the min required capital", async () => {
        expect(poolInfo.params.minRequiredCapital).to.eq(parseUSDC("100000"));
      });

      it("...set the curvature", async () => {
        expect(poolInfo.params.curvature).to.eq(parseEther("0.05"));
      });

      it("...set the minCarapaceRiskPremiumPercent", async () => {
        expect(poolInfo.params.minCarapaceRiskPremiumPercent).to.eq(
          parseEther("0.02")
        );
      });

      it("...set the underlyingRiskPremiumPercent", async () => {
        expect(poolInfo.params.underlyingRiskPremiumPercent).to.eq(
          parseEther("0.1")
        );
      });

      it("...set the underlying token", async () => {
        expect(poolInfo.underlyingToken.toString()).to.eq(USDC.address);
      });

      it("...set the reference loans", async () => {
        expect(poolInfo.referenceLendingPools.toString()).to.eq(
          referenceLendingPools.address
        );
      });

      it("...set the protectionExtensionGracePeriodInSeconds", async () => {
        expect(poolInfo.params.protectionExtensionGracePeriodInSeconds).to.eq(
          getDaysInSeconds(14)
        );
      });

      it("...set the pool state to be DepositOnly", async () => {
        expect((await pool.getPoolInfo()).currentPhase).to.eq(0); // 0 = Deposit Only
      });

      it("...getAllProtections should return empty array", async () => {
        expect((await pool.getAllProtections()).length).to.eq(0);
      });
    });

    describe("updateFloor", () => {
      it("...only the owner should be able to call the updateFloor function", async () => {
        await expect(
          pool.connect(owner).updateFloor(_newFloor)
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });

    describe("updateCeiling", () => {
      it("...only the owner should be able to call the updateCeiling function", async () => {
        await expect(
          pool.connect(owner).updateCeiling(_newCeiling)
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });

    describe("calculateLeverageRatio without any protection buyers or sellers", () => {
      it("...should return 0 when pool has no protection sold", async () => {
        expect(await pool.calculateLeverageRatio()).to.equal(0);
      });
    });

    describe("calculateMaxAllowedProtectionAmount", () => {
      let buyer: Signer;

      before(async () => {
        buyer = await ethers.getImpersonatedSigner(
          "0xcb726f13479963934e91b6f34b6e87ec69c21bb9"
        );
      });

      it("...should return the correct remaining principal", async () => {
        expect(
          await poolInstance
            .connect(buyer)
            .calculateMaxAllowedProtectionAmount(_lendingPool2, 615)
        ).to.eq(parseUSDC("35000"));
      });

      it("...should return the 0 remaining principal for non-owner", async () => {
        // lender doesn't own the NFT
        expect(
          await poolInstance
            .connect(buyer)
            .calculateMaxAllowedProtectionAmount(_lendingPool2, 590)
        ).to.eq(0);
      });

      it("...should return 0 when the buyer owns the NFT for different pool", async () => {
        // see: https://lark.market/tokenDetail?tokenId=142
        // Buyer owns this token, but pool for this token is 0x57686612c601cb5213b01aa8e80afeb24bbd01df

        expect(
          await poolInstance
            .connect(buyer)
            .calculateMaxAllowedProtectionAmount(_lendingPool1, 142)
        ).to.be.eq(0);
      });
    });

    describe("...1st pool cycle", async () => {
      const currentPoolCycleIndex = 0;

      describe("calculateMaxAllowedProtectionDuration", () => {
        it("...should return correct duration", async () => {
          await verifyMaxAllowedProtectionDuration();
        });
      });

      describe("...deposit", async () => {
        const _depositAmount = "40000";
        const _underlyingAmount: BigNumber = parseUSDC(_depositAmount);

        it("...approve 0 USDC to be transferred by the Pool contract", async () => {
          expect(await USDC.approve(pool.address, BigNumber.from(0)))
            .to.emit(USDC, "Approval")
            .withArgs(deployerAddress, pool.address, BigNumber.from(0));
          const _allowanceAmount: number = await USDC.allowance(
            deployerAddress,
            pool.address
          );
          expect(_allowanceAmount.toString()).to.eq(
            BigNumber.from(0).toString()
          );
        });

        it("...fails if pool is paused", async () => {
          before1stDepositSnapshotId = await network.provider.send(
            "evm_snapshot",
            []
          );
          expect(
            await poolCycleManager.getCurrentCycleState(poolInfo.poolId)
          ).to.equal(1); // 1 = Open

          // pause the pool
          await pool.connect(deployer).pause();
          expect(await pool.paused()).to.be.true;
          await expect(
            pool.deposit(_underlyingAmount, deployerAddress)
          ).to.be.revertedWith("Pausable: paused");
        });

        it("...unpause the Pool contract", async () => {
          await pool.unpause();
          expect(await pool.paused()).to.be.false;
        });

        it("...fail if USDC is not approved", async () => {
          await expect(
            pool.deposit(_underlyingAmount, deployerAddress)
          ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
        });

        it("...approve deposit amount to be transferred by deployer to the Pool contract", async () => {
          const _approvalAmt = _underlyingAmount;
          await expect(USDC.approve(pool.address, _approvalAmt))
            .to.emit(USDC, "Approval")
            .withArgs(deployerAddress, pool.address, _approvalAmt);

          expect(await USDC.allowance(deployerAddress, pool.address)).to.eq(
            _approvalAmt
          );
        });

        it("...fail if an SToken receiver is a zero address", async () => {
          await expect(
            pool.deposit(_underlyingAmount, ZERO_ADDRESS)
          ).to.be.revertedWith("ERC20: mint to the zero address");
        });

        it("...1st deposit is successful", async () => {
          await depositAndVerify(deployer, _depositAmount);
        });

        it("...premium should not have accrued", async () => {
          expect(await pool.totalPremiumAccrued()).to.be.eq(0);
        });

        it("...should have correct total seller deposit after 1st deposit", async () => {
          expect(await calculateTotalSellerDeposit()).to.eq(_underlyingAmount);
        });

        it("...movePoolPhase should not move to BuyProtectionOnly state when pool does NOT have min capital required", async () => {
          await expect(pool.connect(deployer).movePoolPhase()).to.not.emit(
            pool,
            "PoolPhaseUpdated"
          );

          expect((await pool.getPoolInfo()).currentPhase).to.eq(0); // 0 = Deposit Only
        });

        it("...2nd deposit by seller is successful", async () => {
          await depositAndVerify(seller, _depositAmount);
        });

        it("...should have correct total seller deposit after 2nd deposit", async () => {
          expect(await calculateTotalSellerDeposit()).to.eq(
            _underlyingAmount.mul(2)
          );
        });

        it("...3rd deposit by account 4 is successful", async () => {
          await depositAndVerify(account4, _depositAmount);
        });

        it("...should have correct total seller deposit after 3rd deposit", async () => {
          expect(await calculateTotalSellerDeposit()).to.eq(
            _underlyingAmount.mul(3)
          );
        });
      });

      describe("...buyProtection when pool is in DepositOnly phase", () => {
        it("...should fail", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith(`PoolInOpenToSellersPhase(${poolInfo.poolId})`);
        });
      });

      describe("...movePoolPhase after deposits", () => {
        it("...should fail if caller is not owner", async () => {
          await expect(
            pool.connect(account4).movePoolPhase()
          ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("...should succeed if caller is owner and pool has min capital required", async () => {
          await expect(pool.connect(deployer).movePoolPhase())
            .to.emit(pool, "PoolPhaseUpdated")
            .withArgs(poolInfo.poolId, 1); // 1 = BuyProtectionOnly

          expect((await pool.getPoolInfo()).currentPhase).to.eq(1);
        });
      });

      describe("calculateLeverageRatio after deposits", () => {
        it("...should return 0 when pool has no protection sellers", async () => {
          expect(await pool.calculateLeverageRatio()).to.equal(0);
        });
      });

      describe("Deposit after pool is in BuyProtectionOnly phase", () => {
        it("...should fail", async () => {
          await expect(
            pool.deposit(parseUSDC("1001"), deployerAddress)
          ).to.be.revertedWith(`PoolInOpenToBuyersPhase(${poolInfo.poolId})`);
        });
      });

      describe("...extendProtection before any protection", () => {
        it("...should fail", async () => {
          await expect(
            pool.connect(_protectionBuyer1).extendProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("NoExpiredProtectionToExtend");
        });
      });

      describe("buyProtection", () => {
        let _purchaseParams: ProtectionPurchaseParamsStruct;

        it("...fails if the lending pool is not supported/added", async () => {
          const buyer = await ethers.getImpersonatedSigner(
            "0x8481a6ebaf5c7dabc3f7e09e44a89531fd31f822"
          );
          const _notSupportedLendingPool =
            "0xC13465CE9Ae3Aa184eB536F04FDc3f54D2dEf277";
          await expect(
            pool.connect(buyer).buyProtection(
              {
                lendingPoolAddress: _notSupportedLendingPool,
                nftLpTokenId: 91,
                protectionAmount: parseUSDC("100"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith(
            `LendingPoolNotSupported("${_notSupportedLendingPool}")`
          );
        });

        it("...pause the pool contract", async () => {
          await pool.pause();
          expect(await pool.paused()).to.be.true;
        });

        it("...fails if the pool contract is paused", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 583,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(10)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("Pausable: paused");
        });

        it("...unpause the pool contract", async () => {
          await pool.unpause();
          expect(await pool.paused()).to.be.false;
        });

        it("...buyer should NOT have any active protection", async () => {
          expect(
            (await pool.getActiveProtections(PROTECTION_BUYER1_ADDRESS)).length
          ).to.eq(0);
        });

        it("...fail if USDC is not approved", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
        });

        it("...approve 2500 USDC premium from protection buyer to the Pool contract", async () => {
          const _approvedAmt = parseUSDC("2500");
          expect(
            await USDC.connect(_protectionBuyer1).approve(
              pool.address,
              _approvedAmt
            )
          )
            .to.emit(USDC, "Approval")
            .withArgs(PROTECTION_BUYER1_ADDRESS, pool.address, _approvedAmt);

          const _allowanceAmount: number = await USDC.allowance(
            PROTECTION_BUYER1_ADDRESS,
            pool.address
          );
          expect(_allowanceAmount).to.eq(_approvedAmt);
        });

        it("...fails when lending pool is not supported", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress:
                  "0x759f097f3153f5d62ff1c2d82ba78b6350f223e3",
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith(
            `LendingPoolNotSupported("0x759f097f3153f5d62FF1C2D82bA78B6350F223e3")`
          );
        });

        it("...fails when buyer doesn't own lending NFT", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 591,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("ProtectionPurchaseNotAllowed");
        });

        it("...fails when protection amount is higher than buyer's loan principal", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("500000"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("ProtectionPurchaseNotAllowed");
        });

        it("...fails when protection expiry is after next pool cycle's end", async () => {
          // we are at day 1 of in cycle 1(30 days), so max possible expiry is 59 days from now
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("50000"),
                protectionDurationInSeconds: getDaysInSeconds(60)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("ProtectionDurationTooLong");
        });

        it("...fails when  premium is higher than specified max protection premium amount", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("100000"),
                protectionDurationInSeconds: getDaysInSeconds(40)
              },
              parseUSDC("2181")
            )
          ).to.be.revertedWith("PremiumExceedsMaxPremiumAmount"); // actual premium: 2186.178950
        });

        it("...1st buy protection is successful", async () => {
          const _initialBuyerAccountId: BigNumber = BigNumber.from(1);
          const _initialPremiumAmountOfAccount: BigNumber = BigNumber.from(0);
          const _premiumTotalOfLendingPoolIdBefore: BigNumber = (
            await pool.getLendingPoolDetail(_lendingPool2)
          )[0];
          const _premiumTotalBefore: BigNumber = await pool.totalPremium();
          const _expectedPremiumAmount = parseUSDC("2186.178950");

          const _protectionAmount = parseUSDC("100000"); // 100,000 USDC
          _purchaseParams = {
            lendingPoolAddress: _lendingPool2,
            nftLpTokenId: 590,
            protectionAmount: _protectionAmount,
            protectionDurationInSeconds: getDaysInSeconds(40)
          };

          const _poolUsdcBalanceBefore = await USDC.balanceOf(pool.address);

          expect(
            await pool
              .connect(_protectionBuyer1)
              .buyProtection(_purchaseParams, parseUSDC("10000"))
          )
            .emit(pool, "PremiumAccrued")
            .to.emit(pool, "BuyerAccountCreated")
            .withArgs(PROTECTION_BUYER1_ADDRESS, _initialBuyerAccountId)
            .to.emit(pool, "CoverageBought")
            .withArgs(
              PROTECTION_BUYER1_ADDRESS,
              _lendingPool2,
              _protectionAmount
            );

          const _premiumAmountOfAccountAfter: BigNumber =
            await pool.getTotalPremiumPaidForLendingPool(
              PROTECTION_BUYER1_ADDRESS,
              _lendingPool2
            );
          const _premiumTotalOfLendingPoolIdAfter: BigNumber = (
            await pool.getLendingPoolDetail(_lendingPool2)
          )[1];
          const _premiumTotalAfter: BigNumber = await pool.totalPremium();
          expect(
            _premiumAmountOfAccountAfter.sub(_initialPremiumAmountOfAccount)
          ).to.eq(_expectedPremiumAmount);

          expect(_premiumTotalBefore.add(_expectedPremiumAmount)).to.eq(
            _premiumTotalAfter
          );
          expect(
            _premiumTotalOfLendingPoolIdBefore.add(_expectedPremiumAmount)
          ).to.eq(_premiumTotalOfLendingPoolIdAfter);
          expect(await pool.totalProtection()).to.eq(_protectionAmount);

          const _poolUsdcBalanceAfter = await USDC.balanceOf(pool.address);
          expect(_poolUsdcBalanceAfter.sub(_poolUsdcBalanceBefore)).to.eq(
            _expectedPremiumAmount
          );
        });

        it("...buyer should have 1 active protection", async () => {
          expect(
            (await pool.getActiveProtections(PROTECTION_BUYER1_ADDRESS)).length
          ).to.eq(1);
        });
      });

      describe("calculateLeverageRatio after 3 deposits & 1 protection", () => {
        it("...should return correct leverage ratio", async () => {
          // 120K / 100K = 1.2
          expect(await pool.calculateLeverageRatio()).to.eq(parseEther("1.2"));
        });
      });

      describe("calculateProtectionPremium after 3 deposits & 1 protection", () => {
        it("...should return correct protection premium", async () => {
          const [_premiumAmount, _isMinPremium] =
            await pool.calculateProtectionPremium({
              lendingPoolAddress: _lendingPool2,
              nftLpTokenId: 590,
              protectionAmount: parseUSDC("100000"),
              protectionDurationInSeconds: getDaysInSeconds(40)
            });

          expect(_premiumAmount).to.eq(parseUSDC("2186.17895"));

          // leverage ratio is out of range, so min premium rate should be used
          expect(await pool.calculateLeverageRatio()).to.be.gt(
            poolInfo.params.leverageRatioCeiling
          );
          expect(_isMinPremium).to.be.true;
        });
      });

      describe("...movePoolPhase + protection purchases", () => {
        before(async () => {
          // Impersonate accounts with lending pool positions
          _protectionBuyer2 = await ethers.getImpersonatedSigner(
            "0xcb726f13479963934e91b6f34b6e87ec69c21bb9"
          );
          _protectionBuyer3 = await ethers.getImpersonatedSigner(
            "0x5cd8c821c080b7340df6969252a979ed416a4e3f"
          );
          _protectionBuyer4 = await ethers.getImpersonatedSigner(
            "0x4902b20bb3b8e7776cbcdcb6e3397e7f6b4e449e"
          );

          // Transfer USDC to buyers from circle account
          // and approve premium to pool from these buyer accounts
          const _premiumAmount = parseUSDC("2000");
          for (const _buyer of [
            _protectionBuyer2,
            _protectionBuyer3,
            _protectionBuyer4
          ]) {
            await transferAndApproveUsdcToPool(_buyer, _premiumAmount);
          }
        });

        it("...should fail if caller is not owner", async () => {
          await expect(pool.connect(seller).movePoolPhase()).to.be.revertedWith(
            "Ownable: caller is not the owner"
          );
        });

        it("...should not move to Open phase when leverage ratio is NOT below ceiling", async () => {
          expect((await pool.getPoolInfo()).currentPhase).to.eq(1); // 1 = BuyProtectionOnly
          expect(await pool.calculateLeverageRatio()).to.be.gt(
            poolInfo.params.leverageRatioCeiling
          );

          await expect(pool.connect(deployer).movePoolPhase()).to.not.emit(
            pool,
            "PoolPhaseUpdated"
          );

          expect((await pool.getPoolInfo()).currentPhase).to.eq(1); // 1 = BuyProtectionOnly
        });

        it("...add 2nd & 3rd protections", async () => {
          // Add bunch of protections
          // protection 2: buyer 2 has principal of 35K USDC with token id: 615
          await pool.connect(_protectionBuyer2).buyProtection(
            {
              lendingPoolAddress: _lendingPool2,
              nftLpTokenId: 615,
              protectionAmount: parseUSDC("20000"),
              protectionDurationInSeconds: getDaysInSeconds(11)
            },
            parseUSDC("10000")
          );
          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer2.getAddress()
              )
            ).length
          ).to.be.eq(1);

          // protection 3: buyer 3 has principal of 63K USDC with token id: 579
          await pool.connect(_protectionBuyer3).buyProtection(
            {
              lendingPoolAddress: _lendingPool2,
              nftLpTokenId: 579,
              protectionAmount: parseUSDC("30000"),
              protectionDurationInSeconds: getDaysInSeconds(30)
            },
            parseUSDC("10000")
          );
          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer3.getAddress()
              )
            ).length
          ).to.be.eq(1);

          expect((await pool.getAllProtections()).length).to.be.eq(3);
          expect((await getActiveProtections()).length).to.eq(3);

          // 200K USDC = 100K + 20K + 30K
          expect(await pool.totalProtection()).to.eq(parseUSDC("150000"));
        });

        it("...should return correct leverage ratio", async () => {
          // 120K / 150K = 0.8
          expect(await pool.calculateLeverageRatio()).to.eq(parseEther("0.8"));
        });

        it("...should succeed if caller is owner and leverage ratio is below ceiling", async () => {
          expect(await pool.calculateLeverageRatio()).to.be.lt(
            poolInfo.params.leverageRatioCeiling
          );
          await expect(pool.connect(deployer).movePoolPhase())
            .to.emit(pool, "PoolPhaseUpdated")
            .withArgs(poolInfo.poolId, 2); // 2 = Open

          expect((await pool.getPoolInfo()).currentPhase).to.eq(2);
        });

        // this unit test is successful but hardhat is failing to generate stacktrace to verify the revert reason
        xit("...4th deposit should fail because of LR breaching ceiling", async () => {
          const _depositAmt = parseUSDC("50000");
          await transferAndApproveUsdcToPool(deployer, _depositAmt);

          // LR = 170K / 150K = 1.13 > 1 (ceiling)
          await expect(
            pool.connect(deployer).deposit(_depositAmt, deployerAddress)
          ).to.be.revertedWith(
            `PoolLeverageRatioTooHigh(${poolInfo.poolId}, 1133333333333333333)`
          );
        });

        it("...add 4th protection", async () => {
          // protection 4: buyer 4 has principal of 158K USDC with token id: 645 in pool
          await pool.connect(_protectionBuyer4).buyProtection(
            {
              lendingPoolAddress: _goldfinchLendingPools[0],
              nftLpTokenId: 645,
              protectionAmount: parseUSDC("50000"),
              protectionDurationInSeconds: getDaysInSeconds(35)
            },
            parseUSDC("10000")
          );
          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer4.getAddress()
              )
            ).length
          ).to.be.eq(1);

          expect((await pool.getAllProtections()).length).to.be.eq(4);
          expect((await getActiveProtections()).length).to.eq(4);

          // 200K USDC = 100K + 20K + 30K + 50K
          expect(await pool.totalProtection()).to.eq(parseUSDC("200000"));
        });

        it("...should return correct leverage ratio after 4th protection purchase", async () => {
          // 120K / 200K = 0.6
          expect(await pool.calculateLeverageRatio()).to.eq(parseEther("0.6"));
        });

        it("...4th deposit should succeed as LR is within range", async () => {
          const _depositAmt = "20000";
          const _underlyingDepositAmt = parseUSDC(_depositAmt);
          await transferAndApproveUsdcToPool(account4, _underlyingDepositAmt);

          // LR = 140K / 200K = 0.7 < 1 (ceiling)
          await depositAndVerify(account4, _depositAmt);
        });
      });

      describe("calculateProtectionPremium with leverage ration within range", () => {
        it("...should return correct protection premium", async () => {
          const [_premiumAmount, _isMinPremium] =
            await pool.calculateProtectionPremium({
              lendingPoolAddress: _lendingPool2,
              nftLpTokenId: 590,
              protectionAmount: parseUSDC("100000"),
              protectionDurationInSeconds: getDaysInSeconds(40)
            });
          expect(_premiumAmount).to.eq(parseUSDC("2186.17895"));

          // leverage ratio is out of range, so min premium rate should be used
          expect(await pool.calculateLeverageRatio())
            .to.be.lt(poolInfo.params.leverageRatioCeiling)
            .and.gt(poolInfo.params.leverageRatioFloor);
          expect(_isMinPremium).to.be.false;
        });
      });

      describe("...requestWithdrawal", async () => {
        const _withdrawalCycleIndex = 2; // current pool cycle index + 2
        const _requestedTokenAmt1 = parseEther("11");
        const _requestedTokenAmt2 = parseEther("5");
        const verifyTotalRequestedWithdrawal = async (
          _expectedTotalWithdrawal: BigNumber
        ) => {
          expect(
            await pool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex)
          ).to.eq(_expectedTotalWithdrawal);
        };
        const verifyRequestedWithdrawal = async (
          _account: Signer,
          _expectedWithdrawal: BigNumber
        ) => {
          expect(
            await pool
              .connect(_account)
              .getRequestedWithdrawalAmount(_withdrawalCycleIndex)
          ).to.eq(_expectedWithdrawal);
        };

        it("...fail when pool is paused", async () => {
          await pool.connect(deployer).pause();
          expect(await pool.paused()).to.be.true;
          const _tokenAmt = parseEther("1");
          await expect(pool.requestWithdrawal(_tokenAmt)).to.be.revertedWith(
            "Pausable: paused"
          );
        });

        it("...unpause the pool", async () => {
          await pool.connect(deployer).unpause();
          expect(await pool.paused()).to.be.false;
        });

        it("...fail when an user has zero balance", async () => {
          const _tokenAmt = parseEther("0.001");
          await expect(
            pool.connect(buyer).requestWithdrawal(_tokenAmt)
          ).to.be.revertedWith(
            `InsufficientSTokenBalance("${buyerAddress}", 0)`
          );
        });

        it("...fail when withdrawal amount is higher than token balance", async () => {
          const _tokenBalance = await pool.balanceOf(sellerAddress);
          const _tokenAmt = _tokenBalance.add(1);
          await expect(
            pool.connect(seller).requestWithdrawal(_tokenAmt)
          ).to.be.revertedWith(
            `InsufficientSTokenBalance("${sellerAddress}", ${_tokenBalance})`
          );
        });

        it("...1st request is successful", async () => {
          await expect(
            pool.connect(seller).requestWithdrawal(_requestedTokenAmt1)
          )
            .to.emit(pool, "WithdrawalRequested")
            .withArgs(
              sellerAddress,
              _requestedTokenAmt1,
              _withdrawalCycleIndex
            );

          await verifyRequestedWithdrawal(seller, _requestedTokenAmt1);

          // withdrawal cycle's total sToken requested amount should be same as the requested amount
          await verifyTotalRequestedWithdrawal(_requestedTokenAmt1);
        });

        it("...2nd request by same user should update existing request", async () => {
          await expect(
            pool.connect(seller).requestWithdrawal(_requestedTokenAmt2)
          )
            .to.emit(pool, "WithdrawalRequested")
            .withArgs(
              sellerAddress,
              _requestedTokenAmt2,
              _withdrawalCycleIndex
            );

          await verifyRequestedWithdrawal(seller, _requestedTokenAmt2);

          // withdrawal cycle's total sToken requested amount should be same as the new requested amount
          await verifyTotalRequestedWithdrawal(_requestedTokenAmt2);
        });

        it("...fail when amount in updating request is higher than token balance", async () => {
          const _tokenBalance = await pool.balanceOf(sellerAddress);
          const _tokenAmt = _tokenBalance.add(1);
          await expect(
            pool.connect(seller).requestWithdrawal(_tokenAmt)
          ).to.be.revertedWith(
            `InsufficientSTokenBalance("${sellerAddress}", ${_tokenBalance})`
          );
        });

        it("...2nd withdrawal request by another user is successful", async () => {
          const _tokenBalance = await pool.balanceOf(account4Address);
          await expect(pool.connect(account4).requestWithdrawal(_tokenBalance))
            .to.emit(pool, "WithdrawalRequested")
            .withArgs(account4Address, _tokenBalance, _withdrawalCycleIndex);

          await verifyRequestedWithdrawal(account4, _tokenBalance);
          await verifyTotalRequestedWithdrawal(
            _requestedTokenAmt2.add(_tokenBalance)
          );
        });
      });

      describe("...withdraw", async () => {
        it("...fails when pool is paused", async () => {
          await pool.connect(deployer).pause();
          expect(await pool.paused()).to.be.true;
          await expect(
            pool.withdraw(parseEther("1"), deployerAddress)
          ).to.be.revertedWith("Pausable: paused");
        });

        it("...unpause the pool", async () => {
          await pool.connect(deployer).unpause();
          expect(await pool.paused()).to.be.false;
        });

        it("...fails because there was no previous cycle", async () => {
          const currentPoolCycle = await poolCycleManager.getCurrentPoolCycle(
            poolInfo.poolId
          );
          await expect(
            pool.withdraw(parseEther("1"), deployerAddress)
          ).to.be.revertedWith(
            `NoWithdrawalRequested("${deployerAddress}", ${currentPoolCycle.currentCycleIndex})`
          );
        });
      });

      describe("pause", () => {
        it("...should allow the owner to pause contract", async () => {
          await expect(pool.connect(owner).pause()).to.be.revertedWith(
            "Ownable: caller is not the owner"
          );
          expect(await pool.connect(deployer).pause()).to.emit(pool, "Paused");
          const _paused: boolean = await pool.paused();
          expect(_paused).to.eq(true);
        });
      });

      describe("unpause", () => {
        it("...should allow the owner to unpause contract", async () => {
          await expect(pool.connect(owner).unpause()).to.be.revertedWith(
            "Ownable: caller is not the owner"
          );
          expect(await pool.connect(deployer).unpause()).to.emit(
            pool,
            "Unpaused"
          );
          const _paused: boolean = await pool.paused();
          expect(_paused).to.eq(false);
        });
      });

      describe("accruePremiumAndExpireProtections", async () => {
        it("...should NOT accrue premium", async () => {
          // no premium should be accrued because there is no new payment
          await expect(pool.accruePremiumAndExpireProtections([])).to.not.emit(
            pool,
            "PremiumAccrued"
          );
        });

        it("...should accrue premium, expire protections & update last accrual timestamp", async () => {
          expect(await pool.totalPremiumAccrued()).to.eq(0);
          const _totalSTokenUnderlyingBefore =
            await pool.totalSTokenUnderlying();

          /// Time needs to be moved ahead by 31 days to apply payment to lending pool
          await moveForwardTimeByDays(31);

          // pay to lending pool
          await payToLendingPoolAddress(_lendingPool2, "100000", USDC);
          await payToLendingPoolAddress(_lendingPool1, "100000", USDC);

          // accrue premium
          expect(await pool.accruePremiumAndExpireProtections([]))
            .to.emit(pool, "PremiumAccrued")
            .to.emit(pool, "ProtectionExpired");

          // 1599.28 + 707.59 + 410.24 + 641.89 = ~3359
          expect(await pool.totalPremiumAccrued())
            .to.be.gt(parseUSDC("3358.99"))
            .and.to.be.lt(parseUSDC("3359"));

          expect(
            (await pool.totalSTokenUnderlying()).sub(
              _totalSTokenUnderlyingBefore
            )
          )
            .to.be.gt(parseUSDC("3358.99"))
            .and.to.be.lt(parseUSDC("3359"));

          expect((await pool.getLendingPoolDetail(_lendingPool2))[0]).to.be.eq(
            await referenceLendingPools.getLatestPaymentTimestamp(_lendingPool2)
          );

          expect((await pool.getLendingPoolDetail(_lendingPool1))[0]).to.be.eq(
            await referenceLendingPools.getLatestPaymentTimestamp(_lendingPool1)
          );
        });

        it("...should mark protections 2 & 3 expired", async () => {
          // 2nd & 3rd protections should be marked expired
          const allProtections = await pool.getAllProtections();
          expect(allProtections.length).to.be.eq(4);
          expect(allProtections[1].expired).to.eq(true);
          expect(allProtections[2].expired).to.eq(true);

          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer2.getAddress()
              )
            ).length
          ).to.be.eq(0);
          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer3.getAddress()
              )
            ).length
          ).to.be.eq(0);

          expect(await getActiveProtections()).to.have.lengthOf(2);
          expect(allProtections[0].expired).to.eq(false);
          expect(allProtections[3].expired).to.eq(false);
          expect(await pool.totalProtection()).to.eq(parseUSDC("150000"));
        });
      });

      describe("deposit after buyProtection", async () => {
        // this unit test is successful but hardhat is failing to generate stacktrace to verify the revert reason
        xit("...fails if it breaches leverage ratio ceiling", async () => {
          expect(await pool.totalProtection()).to.eq(parseUSDC("150000"));

          const depositAmt: BigNumber = parseUSDC("50000");
          await transferAndApproveUsdcToPool(deployer, depositAmt);
          await expect(
            pool.connect(deployer).deposit(depositAmt, deployerAddress)
          ).to.be.revertedWith("PoolLeverageRatioTooHigh");
        });

        it("...succeeds if leverage ratio is below ceiling", async () => {
          const _depositAmount = "5000";
          const _underlyingDepositAmount = parseUSDC(_depositAmount);
          await transferAndApproveUsdcToPool(
            deployer,
            _underlyingDepositAmount
          );
          await pool
            .connect(deployer)
            .deposit(_underlyingDepositAmount, deployerAddress);

          // previous deposits: 140K, new deposit: 5K
          expect(await calculateTotalSellerDeposit()).to.eq(
            parseUSDC("145000")
          );
        });
      });

      describe("buyProtection after deposit", async () => {
        it("...succeeds when total protection is higher than min requirement and leverage ratio higher than floor", async () => {
          // Buyer 1 buys protection of 10K USDC, so approve premium to be paid
          await transferAndApproveUsdcToPool(
            _protectionBuyer1,
            parseUSDC("500")
          );
          await pool.connect(_protectionBuyer1).buyProtection(
            {
              lendingPoolAddress: _lendingPool2,
              // see: https://lark.market/tokenDetail?tokenId=590
              nftLpTokenId: 590, // this token has 420K principal for buyer 1
              protectionAmount: parseUSDC("10000"),
              protectionDurationInSeconds: getDaysInSeconds(15)
            },
            parseUSDC("10000")
          );

          expect(await getActiveProtections()).to.have.lengthOf(3);
          expect(await pool.totalProtection()).to.eq(parseUSDC("160000")); // 100K + 50K + 10K
        });
      });

      describe("extendProtection", () => {
        const _newProtectionAmt = parseUSDC("40000");
        let _newProtectionDurationInSeconds: BigNumber;
        let _expiredProtection3: ProtectionInfoStructOutput;
        let _extensionProtection: ProtectionInfoStructOutput;

        before(async () => {
          _expiredProtection3 = (await pool.getAllProtections())[2];
        });

        it("...should fail when buyer doesn't have expired protection for the lending position - different NFT token id", async () => {
          // expired protection for _protectionBuyer3: lendingPool2, nftLpTokenId: 579
          await expect(
            pool.connect(_protectionBuyer3).extendProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 591,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(10)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("NoExpiredProtectionToExtend");
        });

        it("...should fail when buyer doesn't have expired protection for the lending position - different buyer", async () => {
          // existing protection for _protectionBuyer1: lendingPool2, nftLpTokenId: 590
          await expect(
            pool.connect(owner).extendProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 579,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(10)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("NoExpiredProtectionToExtend");
        });

        it("...should fail when buyer doesn't have expired protection for the lending position - different lending pool", async () => {
          // expired protection for _protectionBuyer3: lendingPool2, nftLpTokenId: 579
          await expect(
            pool.connect(_protectionBuyer3).extendProtection(
              {
                lendingPoolAddress: _lendingPool1,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(10)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("NoExpiredProtectionToExtend");
        });

        it("...should fail when protection extension's duration is longer than next pool cycle's end", async () => {
          // Day 31: we are in day 1 of pool cycle 2, so next pool cycle's(cycle 3) end is at 90 days
          // expired protection's duration is 30 days,
          // so protection extension's with > 60 days duration should fail
          _newProtectionDurationInSeconds = getDaysInSeconds(60) + 1;
          await expect(
            pool.connect(_protectionBuyer3).extendProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 579,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: _newProtectionDurationInSeconds
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("ProtectionDurationTooLong");
        });

        it("...should fail when premium is higher than specified maxProtectionPremium", async () => {
          await expect(
            pool.connect(_protectionBuyer3).extendProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 579,
                protectionAmount: parseUSDC("40000"),
                protectionDurationInSeconds: getDaysInSeconds(59)
              },
              parseUSDC("901")
            )
          ).to.be.revertedWith("PremiumExceedsMaxPremiumAmount");
        });

        it("...should succeed for expired protection within grace period", async () => {
          await transferAndApproveUsdcToPool(
            _protectionBuyer3,
            parseUSDC("2000")
          );

          // Day 31: we are in day 1 of pool cycle 2, so next pool cycle's(cycle 3) end is at 90 days
          // expired protection's duration is 30 days,
          // so protection extension's with < 60 days duration should succeed
          _newProtectionDurationInSeconds = getDaysInSeconds(59);
          await pool.connect(_protectionBuyer3).extendProtection(
            {
              lendingPoolAddress: _lendingPool2,
              nftLpTokenId: 579,
              protectionAmount: _newProtectionAmt,
              protectionDurationInSeconds: _newProtectionDurationInSeconds
            },
            parseUSDC("10000")
          );

          expect(await getActiveProtections()).to.have.lengthOf(4);
          expect(await pool.totalProtection()).to.eq(parseUSDC("200000")); // 100K + 50K + 10K + 40K extension

          _extensionProtection = (await getActiveProtections())[3];
        });

        it("...protection extension should have new protection amount and duration", async () => {
          expect(_extensionProtection.purchaseParams.protectionAmount).to.eq(
            _newProtectionAmt
          );
          expect(
            _extensionProtection.purchaseParams.protectionDurationInSeconds
          ).to.eq(_newProtectionDurationInSeconds);
        });

        it("...protection extension should start now", async () => {
          expect(_extensionProtection.startTimestamp).to.eq(
            await getLatestBlockTimestamp()
          );
        });

        it("...protection extension's lending position must be same as existing protection", async () => {
          expect(_extensionProtection.purchaseParams.lendingPoolAddress).to.eq(
            _expiredProtection3.purchaseParams.lendingPoolAddress
          );
          expect(_extensionProtection.purchaseParams.nftLpTokenId).to.eq(
            _expiredProtection3.purchaseParams.nftLpTokenId
          );
        });

        it("...should fail when expired protection's grace period is over", async () => {
          await moveForwardTimeByDays(15); // grace period is 14 days

          await expect(
            pool.connect(_protectionBuyer3).extendProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 579,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(10)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("CanNotExtendProtectionAfterGracePeriod");
        });
      });

      describe("...before 1st pool cycle is locked", async () => {
        before(async () => {
          // Revert the state of the pool before 1st deposit
          expect(
            await network.provider.send("evm_revert", [
              before1stDepositSnapshotId
            ])
          ).to.eq(true);
        });

        it("...pool cycle should be in open state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 1); // 1 = Open
        });

        it("...can deposit & create withdrawal requests", async () => {
          // create withdrawal requests (cycle after next: 2)
          const _withdrawalAmt = parseEther("10000");

          // Seller1: deposit 20K USDC & request withdrawal of 10K sTokens
          const _depositAmount1 = parseUSDC("20000");
          await transferAndApproveUsdcToPool(seller, _depositAmount1);
          await depositAndRequestWithdrawal(
            seller,
            sellerAddress,
            _depositAmount1,
            _withdrawalAmt
          );

          // Seller2: deposit 40K USDC & request withdrawal of 10K sTokens
          const _depositAmount2 = parseUSDC("40000");
          await transferAndApproveUsdcToPool(owner, _depositAmount2);
          await depositAndRequestWithdrawal(
            owner,
            ownerAddress,
            _depositAmount2,
            _withdrawalAmt
          );

          // Seller3: deposit 40K USDC & request withdrawal of 10K sTokens
          const _depositAmount3 = parseUSDC("40000");
          await transferAndApproveUsdcToPool(account4, _depositAmount3);
          await depositAndRequestWithdrawal(
            account4,
            account4Address,
            _depositAmount3,
            _withdrawalAmt
          );
        });

        it("...can move pool phase to 2nd phase", async () => {
          // after revert, we need to movePoolPhase after initial deposits
          await pool.connect(deployer).movePoolPhase();
          expect((await pool.getPoolInfo()).currentPhase).to.eq(1);
        });

        it("...can buy protections", async () => {
          // Day 1 of Pool cycle 1
          // protection 1 after reset: buyer 4 has principal of 158K USDC with token id: 645 in pool
          await USDC.connect(_protectionBuyer4).approve(
            pool.address,
            parseUSDC("10000")
          );
          await pool.connect(_protectionBuyer4).buyProtection(
            {
              lendingPoolAddress: _lendingPool1,
              nftLpTokenId: 645,
              protectionAmount: parseUSDC("70000"),
              protectionDurationInSeconds: getDaysInSeconds(35)
            },
            parseUSDC("10000")
          );

          await USDC.connect(_protectionBuyer1).approve(
            pool.address,
            parseUSDC("10000")
          );
          await pool.connect(_protectionBuyer1).buyProtection(
            {
              lendingPoolAddress: _lendingPool2,
              nftLpTokenId: 590,
              protectionAmount: parseUSDC("50000"),
              protectionDurationInSeconds: getDaysInSeconds(20)
            },
            parseUSDC("10000")
          );

          expect((await pool.getAllProtections()).length).to.be.eq(2);
          expect((await getActiveProtections()).length).to.eq(2);

          // 100K USDC = 70K + 50K
          expect(await pool.totalProtection()).to.eq(parseUSDC("120000"));
        });

        it("...has correct total requested withdrawal & total sToken underlying", async () => {
          const _withdrawalCycleIndex = currentPoolCycleIndex + 2;

          expect(
            await pool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex)
          ).to.eq(parseEther("30000"));

          expect(await pool.totalSTokenUnderlying()).to.be.eq(
            parseUSDC("100000")
          ); // 3 deposits = 20K + 40K + 40K = 100K USDC
        });
      });

      describe("...1st pool cycle is locked", async () => {
        before(async () => {
          // we need to movePoolPhase
          await pool.connect(deployer).movePoolPhase();
          // Pool should be in OPEN phase
          expect((await pool.getPoolInfo()).currentPhase).to.eq(2);

          // Move pool cycle(open period: 10 days, total duration: 30 days) past 10 days to locked state
          // day 11: 11th day of cycle 1 as state is reverted to before 1st deposit
          await moveForwardTimeByDays(11);
        });

        it("...pool cycle should be in locked state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 2); // 2 = Locked
        });

        it("...deposit should succeed", async () => {
          const _underlyingAmount = parseUSDC("100");

          await transferAndApproveUsdcToPool(seller, _underlyingAmount);
          await expect(
            pool.connect(seller).deposit(_underlyingAmount, sellerAddress)
          )
            .to.emit(pool, "ProtectionSold")
            .withArgs(sellerAddress, _underlyingAmount);
        });

        it("...withdraw should fail", async () => {
          await expect(
            pool.withdraw(parseUSDC("1"), deployerAddress)
          ).to.be.revertedWith(`PoolIsNotOpen(${poolInfo.poolId})`);
        });
      });
    });

    describe("...2nd pool cycle", async () => {
      const currentPoolCycleIndex = 1;

      before(async () => {
        // Move pool cycle(10 days open period, 30 days total duration) to open state of 2nd cycle
        // day 31(20 + 11): 1st day of cycle 2
        await moveForwardTimeByDays(20);
      });

      describe("calculateMaxAllowedProtectionDuration", () => {
        it("...should return correct duration", async () => {
          await verifyMaxAllowedProtectionDuration();
        });
      });

      describe("...open period but no withdrawal", async () => {
        it("...pool cycle should be in open state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 1); // 1 = Open
        });

        it("...fails when withdrawal is not requested", async () => {
          await expect(
            pool.withdraw(parseEther("1"), deployerAddress)
          ).to.be.revertedWith(
            `NoWithdrawalRequested("${deployerAddress}", ${currentPoolCycleIndex})`
          );
        });

        it("...fails when withdrawal is requested just 1 cycle before", async () => {
          await expect(
            pool.connect(seller).withdraw(parseEther("1"), sellerAddress)
          ).to.be.revertedWith(
            `NoWithdrawalRequested("${sellerAddress}", ${currentPoolCycleIndex})`
          );
        });
      });

      describe("...2nd pool cycle is locked", async () => {
        before(async () => {
          // Move 2nd pool cycle(10 days open period, 30 days total duration) to locked state
          // day 42(31 + 11): 12th day of cycle 2
          await moveForwardTimeByDays(11);
        });

        it("...pool cycle should be in locked state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 2); // 2 = Locked
        });

        it("...deposit should succeed", async () => {
          const _underlyingAmount = parseUSDC("100");

          await transferAndApproveUsdcToPool(seller, _underlyingAmount);
          await expect(
            pool.connect(seller).deposit(_underlyingAmount, sellerAddress)
          )
            .to.emit(pool, "ProtectionSold")
            .withArgs(sellerAddress, _underlyingAmount);
        });

        it("...withdraw should fail", async () => {
          await expect(
            pool.withdraw(parseUSDC("1"), deployerAddress)
          ).to.be.revertedWith(`PoolIsNotOpen(${poolInfo.poolId})`);
        });
      });

      describe("...after 2nd pool cycle is locked", async () => {
        it("...can create withdrawal requests for cycle after", async () => {
          // Seller1: deposited 20K USDC in 1st cycle & requested to withdraw 10K. Now request withdrawal of 1000 sTokens
          await pool.connect(seller).requestWithdrawal(parseEther("1000"));
          // Seller2: deposited 40K USDC in 1st cycle & requested to withdraw 10K, now request withdrawal of 2000 sTokens
          await pool.connect(owner).requestWithdrawal(parseEther("2000"));
          // Seller3: deposited 40K USDC in 1st cycle & requested to withdraw 10K, now request withdrawal of 1000 sTokens
          await pool.connect(account4).requestWithdrawal(parseEther("1000"));
        });

        it("...has correct total requested withdrawal", async () => {
          const _withdrawalCycleIndex = currentPoolCycleIndex + 2;

          expect(
            await pool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex)
          ).to.eq(parseEther("4000"));
        });
      });

      describe("claimUnlockedCapital", async () => {
        let lendingPool2: ITranchedPool;
        let _expectedLockedCapital: BigNumber;
        let _totalSTokenUnderlyingBefore: BigNumber;

        const getLatestLockedCapital = async (_lendingPool: string) => {
          return (
            await defaultStateManager.getLockedCapitals(
              poolInstance.address,
              _lendingPool
            )
          )[0];
        };

        async function claimAndVerifyUnlockedCapital(
          account: Signer,
          success: boolean
        ): Promise<BigNumber> {
          const _address = await account.getAddress();
          const _expectedBalance = (await poolInstance.balanceOf(_address))
            .mul(_expectedLockedCapital)
            .div(await poolInstance.totalSupply());

          const _balanceBefore = await USDC.balanceOf(_address);
          await pool.connect(account).claimUnlockedCapital(_address);
          const _balanceAfter = await USDC.balanceOf(_address);

          const _actualBalance = _balanceAfter.sub(_balanceBefore);
          if (success) {
            expect(_actualBalance).to.eq(_expectedBalance);
          }

          return _actualBalance;
        }

        before(async () => {
          snapshotId2 = await network.provider.send("evm_snapshot", []);

          lendingPool2 = (await ethers.getContractAt(
            "ITranchedPool",
            _lendingPool2
          )) as ITranchedPool;
          _totalSTokenUnderlyingBefore =
            await poolInstance.totalSTokenUnderlying();
          _expectedLockedCapital = parseUSDC("50000");

          // pay lending pool 1
          await payToLendingPoolAddress(_lendingPool1, "1000000", USDC);

          // Verify exchange rate is 1 to 1
          expect(await pool.convertToUnderlying(parseEther("1"))).to.eq(
            parseUSDC("1")
          );

          // time has moved forward by more than 30 days, so lending pool 2 is late for payment
          // and state should be transitioned to "Late" and capital should be locked
          await expect(defaultStateManager.assessStates())
            .to.emit(defaultStateManager, "PoolStatesAssessed")
            .to.emit(defaultStateManager, "LendingPoolLocked");
        });

        it("...buyProtection fails when lending pool is late for payment", async () => {
          // day 42: time has moved forward by more than 30 days, so lending pool is late for payment
          await expect(
            pool.connect(_protectionBuyer1).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 590,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: getDaysInSeconds(20)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith(
            `LendingPoolHasLatePayment("0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf")`
          );
        });

        it("...should have locked capital for lending pool 2 after missing a payment", async () => {
          // verify that lending pool 2's capital is locked
          const _lockedCapitalLP2 = await getLatestLockedCapital(_lendingPool2);
          expect(_lockedCapitalLP2.locked).to.be.true;

          // verify that locked capital is equal to total protection bought from lending pool 2
          expect(_lockedCapitalLP2.amount).to.be.eq(_expectedLockedCapital);
        });

        it("...should reduce total sToken underlying by locked capital", async () => {
          expect(
            _totalSTokenUnderlyingBefore.sub(await pool.totalSTokenUnderlying())
          ).to.eq(_expectedLockedCapital);
        });

        it("...should reduce sToken exchange rate", async () => {
          // Verify exchange rate is < 1
          expect(await pool.convertToUnderlying(parseEther("1"))).to.be.lt(
            parseUSDC("1")
          );
        });

        it("...should NOT have locked capital for lending pool 1 before unlocking lending pool 2", async () => {
          // verify that lending pool 1's capital is NOT locked
          const _lockedCapitalLP1 = await getLatestLockedCapital(_lendingPool1);
          expect(_lockedCapitalLP1).to.be.undefined;
        });

        it("...should have unlocked capital after 2 consecutive payments for lending pool 2", async () => {
          // Make 2 consecutive payments to 2nd lending pool
          for (let i = 0; i < 2; i++) {
            await moveForwardTimeByDays(30);
            await payToLendingPool(lendingPool2, "300000", USDC);

            // keep paying lending pool 1
            await payToLendingPoolAddress(_lendingPool1, "300000", USDC);

            if (i === 0) {
              await defaultStateManager.assessStateBatch([
                poolInstance.address
              ]);

              // verify that lending pool 2 is still in late state
              expect(
                await defaultStateManager.getLendingPoolStatus(
                  poolInstance.address,
                  _lendingPool2
                )
              ).to.be.eq(3); // Late
            } else {
              // after second payment, 2nd lending pool should move from Late to Active state
              await expect(
                defaultStateManager.assessStateBatch([poolInstance.address])
              )
                .to.emit(defaultStateManager, "PoolStatesAssessed")
                .to.emit(defaultStateManager, "LendingPoolUnlocked");

              expect(
                await defaultStateManager.getLendingPoolStatus(
                  poolInstance.address,
                  _lendingPool2
                )
              ).to.be.eq(1);
            }
          }

          // verify that lending pool capital is unlocked
          const _unlockedCapital = await getLatestLockedCapital(_lendingPool2);
          expect(_unlockedCapital.locked).to.be.false;

          // verify that unlocked capital is same as previously locked capital
          expect(_unlockedCapital.amount).to.be.eq(_expectedLockedCapital);
        });

        it("...should NOT have locked capital for lending pool 1 after unlocking lending pool 2", async () => {
          // verify that lending pool 1's capital is NOT locked
          const _lockedCapitalLP1 = await getLatestLockedCapital(_lendingPool1);
          expect(_lockedCapitalLP1).to.be.undefined;
        });

        it("...deployer should  NOT be able to claim", async () => {
          expect(await claimAndVerifyUnlockedCapital(deployer, false)).to.be.eq(
            0
          );
        });

        it("...seller should be  able to claim his share of unlocked capital from pool 1", async () => {
          expect(await claimAndVerifyUnlockedCapital(seller, true)).to.be.gt(0);
        });

        it("...seller should  NOT be able to claim again", async () => {
          expect(await claimAndVerifyUnlockedCapital(seller, false)).to.be.eq(
            0
          );
        });

        it("...owner should be  able to claim his share of unlocked capital from pool 1", async () => {
          expect(await claimAndVerifyUnlockedCapital(owner, true)).to.be.gt(0);
        });

        it("...owner should  NOT be able to claim again", async () => {
          expect(await claimAndVerifyUnlockedCapital(owner, false)).to.be.eq(0);
        });

        it("...account 4 should be  able to claim his share of unlocked capital from pool 1", async () => {
          expect(await claimAndVerifyUnlockedCapital(account4, true)).to.be.gt(
            0
          );
          console.log(
            "totalSTokenUnderlying: ",
            await pool.totalSTokenUnderlying()
          );
        });

        it("...account 4 should  NOT be able to claim again", async () => {
          expect(await claimAndVerifyUnlockedCapital(account4, false)).to.be.eq(
            0
          );
        });

        it("...has correct total underlying amount", async () => {
          // 5 deposits = 20K + 40K + 40K + 100 + 100 - 50K of locked capital
          expect(await pool.totalSTokenUnderlying()).to.eq(parseUSDC("50200"));
        });
      });

      describe("buyProtection after lock/unlock", async () => {
        before(async () => {
          // revert to snapshot
          expect(
            await network.provider.send("evm_revert", [snapshotId2])
          ).to.be.eq(true);

          snapshotId2 = await network.provider.send("evm_snapshot", []);

          await payToLendingPoolAddress(_lendingPool1, "1000000", USDC);
          await payToLendingPoolAddress(_lendingPool2, "1000000", USDC);
        });

        it("...has correct total underlying amount", async () => {
          // 5 deposits = 20K + 40K + 40K + 100 + 100
          expect(await pool.totalSTokenUnderlying()).to.eq(parseUSDC("100200"));
        });

        it("...accrue premium and expire protections", async () => {
          // should expire 2 protections
          expect((await getActiveProtections()).length).to.eq(2);
          await pool.accruePremiumAndExpireProtections([]);
          expect((await getActiveProtections()).length).to.eq(0);
        });

        it("...can buy protections", async () => {
          // Day 42: 12th day of Pool cycle 2
          // protection 4: buyer 4 has principal of 158K USDC with token id: 645 in pool
          await USDC.connect(_protectionBuyer4).approve(
            pool.address,
            parseUSDC("10000")
          );
          await pool.connect(_protectionBuyer4).buyProtection(
            {
              lendingPoolAddress: _lendingPool1,
              nftLpTokenId: 645,
              protectionAmount: parseUSDC("70000"),
              protectionDurationInSeconds: getDaysInSeconds(35)
            },
            parseUSDC("10000")
          );

          expect((await pool.getAllProtections()).length).to.be.eq(3);
          expect((await getActiveProtections()).length).to.eq(1);
          expect(await pool.totalProtection()).to.eq(parseUSDC("70000"));
        });
      });

      describe("extendProtection after purchase limit", async () => {
        it("...extendProtection should fail when protection extension's duration is longer than 3rd pool cycle's end", async () => {
          // we are in day 42: 12th day of pool cycle 2, so next(3rd) pool cycle's end is after 48 days at 90 days
          // expired protection's(protection after revert) duration is 35 days,
          // so protection extension's with > 13 days duration should fail
          const _newProtectionDurationInSeconds = getDaysInSeconds(13) + 1;
          await expect(
            pool.connect(_protectionBuyer4).extendProtection(
              {
                lendingPoolAddress: _lendingPool1,
                nftLpTokenId: 645,
                protectionAmount: parseUSDC("101"),
                protectionDurationInSeconds: _newProtectionDurationInSeconds
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("ProtectionDurationTooLong");
        });

        it("...extendProtection should succeed when duration is less than 3rd pool cycle end", async () => {
          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer4.getAddress()
              )
            ).length
          ).to.be.eq(1);

          await pool.connect(_protectionBuyer4).extendProtection(
            {
              lendingPoolAddress: _lendingPool1,
              nftLpTokenId: 645,
              protectionAmount: parseUSDC("20000"),
              protectionDurationInSeconds: getDaysInSeconds(13)
            },
            parseUSDC("10000")
          );

          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer4.getAddress()
              )
            ).length
          ).to.be.eq(2);
        });
      });
    });

    describe("...3rd pool cycle", async () => {
      const currentPoolCycleIndex = 2;

      before(async () => {
        // Move pool cycle(10 days open period, 30 days total duration) to open state (next pool cycle)
        // day 62(42 + 20): 2nd day of cycle 3
        await moveForwardTimeByDays(20);
      });

      describe("calculateMaxAllowedProtectionDuration", () => {
        it("...should return correct duration", async () => {
          await verifyMaxAllowedProtectionDuration();
        });
      });

      describe("...open period with withdrawal", async () => {
        it("...pool cycle should be in open state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 1); // 1 = Open
        });

        it("...has correct total requested withdrawal amount", async () => {
          expect(
            await pool.getTotalRequestedWithdrawalAmount(currentPoolCycleIndex)
          ).to.eq(parseEther("30000"));
        });

        it("...has correct total underlying amount", async () => {
          expect(await pool.totalSTokenUnderlying()).to.be.gt(
            parseUSDC("50200")
          ); // 5 deposits = 20K + 40K + 40K + 100 + 100 - 50K of locked capital + accrued premium
        });

        it("...fails when withdrawal amount is higher than requested amount", async () => {
          // Seller has requested 10K sTokens in 1st cycle
          const withdrawalAmt = parseEther("10001");
          await expect(
            pool.connect(seller).withdraw(withdrawalAmt, sellerAddress)
          ).to.be.revertedWith(
            `WithdrawalHigherThanRequested("${sellerAddress}", ${parseEther(
              "10000"
            ).toString()})`
          );
        });

        it("...is successful for 1st seller", async () => {
          // Seller has requested 10K sTokens in previous cycle
          const withdrawalAmt = parseEther("10000");
          await verifyWithdrawal(seller, withdrawalAmt);
        });

        it("...fails for second withdrawal by 1st seller", async () => {
          // Seller has withdrawn all requested tokens, so withdrawal request should be removed
          expect(
            await pool
              .connect(seller)
              .getRequestedWithdrawalAmount(currentPoolCycleIndex)
          ).to.eq(0);
          await expect(
            pool.connect(seller).withdraw(parseEther("1"), sellerAddress)
          ).to.be.revertedWith(
            `NoWithdrawalRequested("${sellerAddress}", ${currentPoolCycleIndex})`
          );
        });

        it("...is successful for 2nd seller", async () => {
          // 2nd seller (Owner account) has requested 10K sTokens in 1st cycle
          const withdrawalAmt = parseEther("10000");
          await verifyWithdrawal(owner, withdrawalAmt);
        });

        it("...fails for second withdrawal by 2nd seller", async () => {
          // 2nd Seller(Owner account) has withdrawn all requested tokens, so withdrawal request should be removed
          expect(
            await pool
              .connect(owner)
              .getRequestedWithdrawalAmount(currentPoolCycleIndex)
          ).to.eq(0);
          await expect(
            pool.connect(owner).withdraw(parseEther("1"), ownerAddress)
          ).to.be.revertedWith(
            `NoWithdrawalRequested("${ownerAddress}", ${currentPoolCycleIndex})`
          );
        });

        it("...is successful for 3rd seller with 2 transactions", async () => {
          const sTokenBalanceBefore = await pool.balanceOf(account4Address);
          // 3rd seller (Account4) has requested total 10K sTokens in 1st cycle,
          // so partial withdrawal should be possible
          await verifyWithdrawal(account4, parseEther("6000"));
          await verifyWithdrawal(account4, parseEther("3000"));
        });

        it("...fails for third withdrawal by 3rd seller", async () => {
          // 3rd Seller(account4) has withdrawn 9000 out of 10K requested tokens,
          // so withdrawal request should exist with 1000 sTokens remaining
          expect(
            await pool
              .connect(account4)
              .getRequestedWithdrawalAmount(currentPoolCycleIndex)
          ).to.eq(parseEther("1000"));
          // withdrawing more(1001) sTokens than remaining requested should fail
          await expect(
            pool.connect(account4).withdraw(parseEther("1001"), account4Address)
          ).to.be.revertedWith(
            `WithdrawalHigherThanRequested("${account4Address}", ${parseEther(
              "1000"
            )})`
          );
        });
      });

      describe("buyProtection after protection purchase limit", async () => {
        it("...should fail because of protection purchase limit for new buyer", async () => {
          // make lending pool payment current, so buyProtection should NOT fail for late payment,
          // but it should fail for NEW buyer because of protection purchase limit: past 60 days
          await payToLendingPoolAddress(_lendingPool2, "1000000", USDC);
          // protection 3: buyer 3 has principal of 63K USDC with token id: 579
          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer3.getAddress()
              )
            ).length
          ).to.be.eq(0);
          await expect(
            pool.connect(_protectionBuyer3).buyProtection(
              {
                lendingPoolAddress: _lendingPool2,
                nftLpTokenId: 579,
                protectionAmount: parseUSDC("30000"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("ProtectionPurchaseNotAllowed");
        });

        it("...should fail because of PoolLeverageRatioTooLow", async () => {
          // lending pool protection purchase limit is 90 days
          await payToLendingPoolAddress(_lendingPool1, "1000000", USDC);
          expect(
            (
              await pool.getActiveProtections(
                await _protectionBuyer4.getAddress()
              )
            ).length
          ).to.be.eq(2);

          await expect(
            pool.connect(_protectionBuyer4).buyProtection(
              {
                lendingPoolAddress: _lendingPool1,
                nftLpTokenId: 645,
                protectionAmount: parseUSDC("60000"),
                protectionDurationInSeconds: getDaysInSeconds(11)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("PoolLeverageRatioTooLow");
        });

        it("...deposit should succeed in open phase after lock/unlock", async () => {
          const _totalSTokenUnderlyingBefore =
            await pool.totalSTokenUnderlying();

          const _depositAmount = parseUSDC("10000");
          await transferAndApproveUsdcToPool(deployer, _depositAmount);
          await pool.connect(deployer).deposit(_depositAmount, deployerAddress);

          const _totalSTokenUnderlyingAfter =
            await pool.totalSTokenUnderlying();
          expect(
            _totalSTokenUnderlyingAfter.sub(_totalSTokenUnderlyingBefore)
          ).to.be.eq(_depositAmount);
        });
      });

      describe("buyProtection after after adding new lending pool", async () => {
        const _lendingPool3 = "0x89d7c618a4eef3065da8ad684859a547548e6169";
        const _protectionBuyerAddress =
          "0x3371E5ff5aE3f1979074bE4c5828E71dF51d299c";
        let _protectionBuyer: Signer;

        before(async () => {
          _protectionBuyer = await ethers.getImpersonatedSigner(
            _protectionBuyerAddress
          );

          // Ensure lending pool is current on payment
          await payToLendingPoolAddress(_lendingPool3, "3000000", USDC);
          await referenceLendingPools
            .connect(deployer)
            .addReferenceLendingPool(_lendingPool3, 0, 30);

          expect(
            (await referenceLendingPools.getLendingPools()).length
          ).to.be.eq(3);

          await defaultStateManager.assessStates();
        });

        it("...buyProtection in new pool should succeed", async () => {
          expect(
            (await pool.getActiveProtections(_protectionBuyerAddress)).length
          ).to.be.eq(0);

          await deployer.sendTransaction({
            to: _protectionBuyerAddress,
            value: ethers.utils.parseEther("10")
          });

          await transferAndApproveUsdcToPool(
            _protectionBuyer,
            parseUSDC("1000")
          );
          await pool.connect(_protectionBuyer).buyProtection(
            {
              lendingPoolAddress: _lendingPool3,
              nftLpTokenId: 717,
              protectionAmount: parseUSDC("30000"),
              protectionDurationInSeconds: getDaysInSeconds(30)
            },
            parseUSDC("10000")
          );

          expect(
            (await pool.getActiveProtections(_protectionBuyerAddress)).length
          ).to.be.eq(1);
        });

        it("...buyProtection in new pool should fail when pool is in LateWithinGracePeriod state", async () => {
          // Ensure lending pool is late on payment
          const lastPaymentTimestamp =
            await referenceLendingPools.getLatestPaymentTimestamp(
              _lendingPool3
            );

          await setNextBlockTimestamp(
            lastPaymentTimestamp.add(getDaysInSeconds(30).add(60 * 60)) // late by 1 hour
          );

          await defaultStateManager.assessStates();
          await expect(
            pool.connect(_protectionBuyer).buyProtection(
              {
                lendingPoolAddress: _lendingPool3,
                nftLpTokenId: 717,
                protectionAmount: parseUSDC("30000"),
                protectionDurationInSeconds: getDaysInSeconds(30)
              },
              parseUSDC("10000")
            )
          ).to.be.revertedWith("LendingPoolHasLatePayment");
        });
      });
    });

    after(async () => {
      // Revert the EVM state before pool cycle tests in "before 1st pool cycle is locked"
      // to revert the time forwarded in the tests

      expect(await network.provider.send("evm_revert", [snapshotId2])).to.be.eq(
        true
      );

      await pool.accruePremiumAndExpireProtections([]);
    });
  });
};

export { testPool };
