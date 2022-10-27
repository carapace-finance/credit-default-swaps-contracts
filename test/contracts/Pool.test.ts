import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ethers, network } from "hardhat";
import { parseEther } from "ethers/lib/utils";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { PoolInfoStructOutput } from "../../typechain-types/contracts/interfaces/IPool";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ProtectionPurchaseParamsStruct } from "../../typechain-types/contracts/interfaces/IReferenceLendingPools";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import {
  getLatestBlockTimestamp,
  getUnixTimestampAheadByDays,
  moveForwardTimeByDays
} from "../utils/time";
import { parseUSDC, getUsdcContract, impersonateCircle } from "../utils/usdc";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";
import { ICreditLine } from "../../typechain-types/contracts/external/goldfinch/ICreditLine";
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
    let beforePoolCycleTestSnapshotId: string;
    let _protectionBuyer1: Signer;
    let circleAccount: Signer;
    let lendingPoolAddress: string;

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

    const transferAndApproveUsdc = async (
      _buyer: Signer,
      _amount: BigNumber
    ) => {
      await USDC.connect(circleAccount).transfer(
        await _buyer.getAddress(),
        _amount
      );
      await USDC.connect(_buyer).approve(pool.address, _amount);
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

    before("setup", async () => {
      deployerAddress = await deployer.getAddress();
      sellerAddress = await seller.getAddress();
      buyerAddress = await buyer.getAddress();
      ownerAddress = await owner.getAddress();
      account4Address = await account4.getAddress();
      poolInfo = await pool.getPoolInfo();
      USDC = getUsdcContract(deployer);

      // Impersonate CIRCLE account and transfer some USDC to test accounts
      circleAccount = await impersonateCircle();
      USDC.connect(circleAccount).transfer(
        deployerAddress,
        parseUSDC("1000000")
      );
      USDC.connect(circleAccount).transfer(ownerAddress, parseUSDC("20000"));
      USDC.connect(circleAccount).transfer(sellerAddress, parseUSDC("20000"));
      USDC.connect(circleAccount).transfer(account4Address, parseUSDC("20000"));

      // 420K principal for token 590
      _protectionBuyer1 = await getGoldfinchLender1();

      USDC.connect(circleAccount).transfer(
        PROTECTION_BUYER1_ADDRESS,
        parseUSDC("1000000")
      );

      // these lending pools have been already added to referenceLendingPools instance
      // Lending pool details: https://app.goldfinch.finance/pools/0xd09a57127bc40d680be7cb061c2a6629fe71abef
      // Lending pool tokens: https://lark.market/?attributes%5BPool+Address%5D=0xd09a57127bc40d680be7cb061c2a6629fe71abef
      let goldfinchLendingPools: string[] =
        await referenceLendingPools.getLendingPools();
      lendingPoolAddress = goldfinchLendingPools[1];
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
        expect(poolInfo.params.leverageRatioFloor).to.eq(parseEther("0.1"));
      });
      it("...set the leverage ratio ceiling", async () => {
        expect(poolInfo.params.leverageRatioCeiling).to.eq(parseEther("0.2"));
      });
      it("...set the leverage ratio buffer", async () => {
        expect(poolInfo.params.leverageRatioBuffer).to.eq(parseEther("0.05"));
      });
      it("...set the min required capital", async () => {
        expect(poolInfo.params.minRequiredCapital).to.eq(parseUSDC("5000"));
      });
      it("...set the min required protection", async () => {
        expect(poolInfo.params.minRequiredProtection).to.eq(
          parseUSDC("200000")
        );
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

    describe("...1st pool cycle", async () => {
      describe("...deposit", async () => {
        let _totalSTokenUnderlyingBefore: BigNumber;
        let _poolUsdcBalanceBefore: BigNumber;
        let _totalSTokenUnderlyingAfter: BigNumber;
        let _poolUsdcBalanceAfter: BigNumber;
        const _underlyingAmount: BigNumber = parseUSDC("3000");

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

        it("...approve 3K USDC to be transferred by deployer to the Pool contract", async () => {
          const _approvalAmt = parseUSDC("3000"); // 1 million USDC
          expect(await USDC.approve(pool.address, _approvalAmt))
            .to.emit(USDC, "Approval")
            .withArgs(deployerAddress, pool.address, _approvalAmt);
          const _allowanceAmount: number = await USDC.allowance(
            deployerAddress,
            pool.address
          );
          expect(_allowanceAmount).to.eq(_approvalAmt);
        });

        it("...fail if an SToken receiver is a zero address", async () => {
          await expect(
            pool.deposit(_underlyingAmount, ZERO_ADDRESS)
          ).to.be.revertedWith("ERC20: mint to the zero address");
        });

        it("...is successful", async () => {
          _totalSTokenUnderlyingBefore = await pool.totalSTokenUnderlying();
          _poolUsdcBalanceBefore = await USDC.balanceOf(pool.address);

          await expect(pool.deposit(_underlyingAmount, deployerAddress))
            .to.emit(pool, "PremiumAccrued")
            .to.emit(pool, "ProtectionSold")
            .withArgs(deployerAddress, _underlyingAmount);
        });

        it("...premium should not have accrued", async () => {
          expect(await pool.totalPremiumAccrued()).to.be.eq(0);
        });

        it("...deployer receives same sTokens as deposit", async () => {
          // sTokens balance of seller should be same as underlying deposit amount
          expect(await pool.balanceOf(deployerAddress)).to.eq(
            parseEther("3000")
          );
        });

        it("...should return 3000 USDC as total seller deposit", async () => {
          expect(await calculateTotalSellerDeposit()).to.eq(_underlyingAmount);
        });

        // Pool have 3000 USDC from the deposit
        it("...should return total underlying amount received as deposit", async () => {
          const _totalUnderlying: BigNumber = await USDC.balanceOf(
            pool.address
          );
          expect(_totalUnderlying).to.eq(_underlyingAmount);
        });

        it("...pool should have correct total sToken underlying amount after 1st deposit", async () => {
          _totalSTokenUnderlyingAfter = await pool.totalSTokenUnderlying();
          expect(
            _totalSTokenUnderlyingAfter.sub(_totalSTokenUnderlyingBefore)
          ).to.eq(_underlyingAmount);
        });

        it("...pool should have correct USDC balance after 1st deposit", async () => {
          _poolUsdcBalanceAfter = await USDC.balanceOf(pool.address);
          expect(_poolUsdcBalanceAfter.sub(_poolUsdcBalanceBefore)).to.eq(
            _underlyingAmount
          );
        });

        it("...should convert sToken shares to correct underlying amount for deployer", async () => {
          // Deployer should receive same USDC amt as deposited because no premium accrued
          expect(
            await pool.convertToUnderlying(
              await pool.balanceOf(deployerAddress)
            )
          ).to.be.eq(_underlyingAmount);
        });

        it("...buyProtection should fail when pool does not have min capital required", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection({
              lendingPoolAddress: lendingPoolAddress,
              nftLpTokenId: 590,
              protectionAmount: parseUSDC("101"),
              protectionExpirationTimestamp: await getUnixTimestampAheadByDays(
                30
              )
            })
          ).to.be.revertedWith(`PoolHasNoMinCapitalRequired`);
        });

        it("...2nd deposit by seller is successful", async () => {
          _totalSTokenUnderlyingBefore = await pool.totalSTokenUnderlying();
          _poolUsdcBalanceBefore = await USDC.balanceOf(pool.address);

          await transferAndApproveUsdc(seller, _underlyingAmount);
          await expect(
            pool.connect(seller).deposit(_underlyingAmount, sellerAddress)
          )
            .to.emit(pool, "PremiumAccrued")
            .to.emit(pool, "ProtectionSold")
            .withArgs(sellerAddress, _underlyingAmount);

          // 2nd deposit will receive same sTokens shares as the first deposit because of no premium accrued
          expect(await pool.balanceOf(sellerAddress)).to.eq(parseEther("3000"));
        });

        it("...pool should have correct total sToken underlying amount after 2nd deposit", async () => {
          _totalSTokenUnderlyingAfter = await pool.totalSTokenUnderlying();
          expect(
            _totalSTokenUnderlyingAfter.sub(_totalSTokenUnderlyingBefore)
          ).to.eq(_underlyingAmount);
        });

        it("...pool should have correct USDC balance after 2nd deposit", async () => {
          _poolUsdcBalanceAfter = await USDC.balanceOf(pool.address);
          expect(_poolUsdcBalanceAfter.sub(_poolUsdcBalanceBefore)).to.eq(
            _underlyingAmount
          );
        });

        it("...should return 6000 USDC as total seller deposit", async () => {
          expect(await calculateTotalSellerDeposit()).to.eq(
            _underlyingAmount.mul(2)
          );
        });

        it("...should convert sToken shares to correct underlying amount for seller", async () => {
          // Seller should receive same USDC amt as deposited because no premium accrued
          expect(
            await pool.convertToUnderlying(await pool.balanceOf(sellerAddress))
          ).to.be.eq(_underlyingAmount);
        });

        // for some reason, this test fails without hardhat generating stacktrace
        xit("...fail if deposit causes to breach leverage ratio ceiling", async () => {
          expect(await pool.totalProtection()).to.eq(parseUSDC("100000"));
          const depositAmt: BigNumber = parseUSDC("52000");
          await expect(
            pool.deposit(depositAmt, sellerAddress)
          ).to.be.revertedWith("PoolLeverageRatioTooHigh");
        });
      });

      describe("calculateLeverageRatio after deposits and no protection", () => {
        it("...should return 0 when pool has no protection sellers", async () => {
          expect(await pool.calculateLeverageRatio()).to.equal(0);
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
            pool.connect(buyer).buyProtection({
              lendingPoolAddress: _notSupportedLendingPool,
              nftLpTokenId: 91,
              protectionAmount: parseUSDC("100"),
              protectionExpirationTimestamp: getUnixTimestampAheadByDays(30)
            })
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
            pool.connect(_protectionBuyer1).buyProtection({
              lendingPoolAddress: lendingPoolAddress,
              nftLpTokenId: 583,
              protectionAmount: parseUSDC("101"),
              protectionExpirationTimestamp: await getUnixTimestampAheadByDays(
                10
              )
            })
          ).to.be.revertedWith("Pausable: paused");
        });

        it("...unpause the pool contract", async () => {
          await pool.unpause();
          expect(await pool.paused()).to.be.false;
        });

        it("...the buyer account doesn't exist for the msg.sender", async () => {
          expect(
            await pool.ownerAddressToBuyerAccountId(deployerAddress)
          ).to.eq(0);
        });

        it("...fail if USDC is not approved", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection({
              lendingPoolAddress: lendingPoolAddress,
              nftLpTokenId: 590,
              protectionAmount: parseUSDC("101"),
              protectionExpirationTimestamp: await getUnixTimestampAheadByDays(
                30
              )
            })
          ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
        });

        it("...approve 2500 USDC to be transferred to the Pool contract", async () => {
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
            pool.connect(_protectionBuyer1).buyProtection({
              lendingPoolAddress: "0x759f097f3153f5d62ff1c2d82ba78b6350f223e3",
              nftLpTokenId: 590,
              protectionAmount: parseUSDC("101"),
              protectionExpirationTimestamp: await getUnixTimestampAheadByDays(
                30
              )
            })
          ).to.be.revertedWith(
            `LendingPoolNotSupported("0x759f097f3153f5d62FF1C2D82bA78B6350F223e3")`
          );
        });

        it("...fails when buyer doesn't own lending NFT", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection({
              lendingPoolAddress: lendingPoolAddress,
              nftLpTokenId: 591,
              protectionAmount: parseUSDC("101"),
              protectionExpirationTimestamp: await getUnixTimestampAheadByDays(
                30
              )
            })
          ).to.be.revertedWith("ProtectionPurchaseNotAllowed");
        });

        it("...fails when protection amount is higher than buyer's loan principal", async () => {
          await expect(
            pool.connect(_protectionBuyer1).buyProtection({
              lendingPoolAddress: lendingPoolAddress,
              nftLpTokenId: 590,
              protectionAmount: parseUSDC("500000"),
              protectionExpirationTimestamp: await getUnixTimestampAheadByDays(
                30
              )
            })
          ).to.be.revertedWith("ProtectionPurchaseNotAllowed");
        });

        it("...create a new buyer account and buy protection", async () => {
          const _initialBuyerAccountId: BigNumber = BigNumber.from(1);
          const _initialPremiumAmountOfAccount: BigNumber = BigNumber.from(0);
          const _premiumTotalOfLendingPoolIdBefore: BigNumber = (
            await pool.getLendingPoolDetail(lendingPoolAddress)
          )[0];
          const _premiumTotalBefore: BigNumber = await pool.totalPremium();
          const _expectedPremiumAmount = parseUSDC("2186.178896");

          const _protectionAmount = parseUSDC("100000"); // 100,000 USDC
          _purchaseParams = {
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 590,
            protectionAmount: _protectionAmount,
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(40)
          };

          const _poolUsdcBalanceBefore = await USDC.balanceOf(pool.address);

          expect(
            await pool.connect(_protectionBuyer1).buyProtection(_purchaseParams)
          )
            .emit(pool, "PremiumAccrued")
            .to.emit(pool, "BuyerAccountCreated")
            .withArgs(PROTECTION_BUYER1_ADDRESS, _initialBuyerAccountId)
            .to.emit(pool, "CoverageBought")
            .withArgs(
              PROTECTION_BUYER1_ADDRESS,
              lendingPoolAddress,
              _protectionAmount
            );

          const _premiumAmountOfAccountAfter: BigNumber =
            await pool.buyerAccounts(
              _initialBuyerAccountId,
              lendingPoolAddress
            );
          const _premiumTotalOfLendingPoolIdAfter: BigNumber = (
            await pool.getLendingPoolDetail(lendingPoolAddress)
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

        it("...the buyer account for the msg.sender exists already", async () => {
          const _noBuyerAccountExist: boolean =
            (await pool
              .ownerAddressToBuyerAccountId(deployerAddress)
              .toString()) === "0";
          expect(_noBuyerAccountExist).to.eq(false);
        });

        it("...fail when total protection crosses min requirement with leverage ratio breaching floor", async () => {
          const _protectionAmount = parseUSDC("110000");
          await USDC.connect(_protectionBuyer1).approve(
            pool.address,
            parseUSDC("2500")
          );
          _purchaseParams = {
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 590,
            protectionAmount: _protectionAmount,
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(30)
          };

          await expect(
            pool.connect(_protectionBuyer1).buyProtection(_purchaseParams)
          ).to.be.revertedWith("PoolLeverageRatioTooLow");
        });
      });

      describe("calculateLeverageRatio after 2 deposits & 1 protection", () => {
        it("...should return correct leverage ratio", async () => {
          // 6000 / 100000 = 0.06
          expect(await pool.calculateLeverageRatio()).to.eq(parseEther("0.06"));
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

        it("...2nd request by another user is successful", async () => {
          const _underlyingAmount = parseUSDC("20");
          await USDC.connect(owner).approve(pool.address, _underlyingAmount);
          await pool.connect(owner).deposit(_underlyingAmount, ownerAddress);
          const _tokenBalance = await pool.balanceOf(ownerAddress);
          await expect(pool.connect(owner).requestWithdrawal(_tokenBalance))
            .to.emit(pool, "WithdrawalRequested")
            .withArgs(ownerAddress, _tokenBalance, _withdrawalCycleIndex);

          await verifyRequestedWithdrawal(owner, _tokenBalance);
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

      xdescribe("accruePremiumAndExpireProtections", async () => {
        it("...should NOT accrue premium", async () => {
          // no premium should be accrued because there is no new payment
          await expect(pool.accruePremiumAndExpireProtections()).to.not.emit(
            pool,
            "PremiumAccrued"
          );
        });

        it("...should accrue premium and update last accrual timestamp", async () => {
          const totalPremiumAccruedBefore = await pool.totalPremiumAccrued();
          expect(totalPremiumAccruedBefore).to.eq(0);

          /// Time needs to be moved ahead by 31 days to apply payment to lending pool
          await moveForwardTimeByDays(31);

          // pay to lending pool
          await payToLendingPoolAddress(lendingPoolAddress, "100000", USDC);

          // accrue premium
          expect(await pool.accruePremiumAndExpireProtections()).to.emit(
            pool,
            "PremiumAccrued"
          );

          expect(await pool.totalPremiumAccrued()).to.be.eq(
            parseUSDC("1599.282240")
          );

          expect(
            (await pool.getLendingPoolDetail(lendingPoolAddress))[0]
          ).to.be.eq(
            await referenceLendingPools.getLatestPaymentTimestamp(
              lendingPoolAddress
            )
          );

          expect((await pool.getAllProtections()).length).to.eq(1);
        });

        xit("...should remove single expired protection", async () => {
          const protectionCount = (await pool.getAllProtections()).length;
          expect(protectionCount).to.eq(1);
          expect(await pool.totalProtection()).to.eq(parseUSDC("100000"));

          const _protectionAmount = parseUSDC("20000");
          const _purchaseParams = {
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 590,
            protectionAmount: _protectionAmount,
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(10)
          };

          const _premiumPaid = parseUSDC("418.617884");
          await pool.connect(_protectionBuyer1).buyProtection(_purchaseParams);

          expect(await pool.totalProtection()).to.eq(parseUSDC("120000")); // 120K
          expect(await pool.getAllProtections()).to.have.lengthOf(2);

          /// Time needs to be moved ahead by 31 days to apply payment to lending pool
          await moveForwardTimeByDays(31);

          // pay to lending pool
          await payToLendingPoolAddress(lendingPoolAddress, "100000", USDC);

          // 2nd protection should be expired and removed
          const _totalPremiumAccruedBefore = await pool.totalPremiumAccrued();
          await pool.accruePremiumAndExpireProtections();

          expect(await pool.getAllProtections()).to.have.lengthOf(1);
          expect(await pool.totalProtection()).to.eq(parseUSDC("100000"));

          // all premium for expired protection should be accrued
          const _totalPremiumAccruedAfter = await pool.totalPremiumAccrued();
          expect(
            _totalPremiumAccruedAfter.sub(_totalPremiumAccruedBefore)
          ).to.be.gt(_premiumPaid);
        });

        xit("...should remove multiple expired protection", async () => {
          const protectionCount = (await pool.getAllProtections()).length;
          expect(protectionCount).to.eq(1);
          expect(await pool.totalProtection()).to.eq(parseUSDC("100000"));

          // Impersonate accounts with lending pool positions
          const _buyer1 = await ethers.getImpersonatedSigner(
            "0xcb726f13479963934e91b6f34b6e87ec69c21bb9"
          );
          const _buyer2 = await ethers.getImpersonatedSigner(
            "0x5cd8c821c080b7340df6969252a979ed416a4e3f"
          );
          const _buyer3 = await ethers.getImpersonatedSigner(
            "0xb5a790758cdb6644305d1cf368b67bbba4c9a68c"
          );

          // Transfer USDC to buyers from circle account
          // and approve premium to pool from these buyer accounts
          const _premiumAmount = parseUSDC("2000");
          for (const _buyer of [_buyer1, _buyer2, _buyer3]) {
            await transferAndApproveUsdc(_buyer, _premiumAmount);
          }

          // Add bunch of protections
          // buyer 1 has principal of 35K USDC with token id: 615
          await pool.connect(_buyer1).buyProtection({
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 615,
            protectionAmount: parseUSDC("20000"),
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(11)
          });

          // buyer 2 has principal of 63K USDC with token id: 579
          await pool.connect(_buyer2).buyProtection({
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 579,
            protectionAmount: parseUSDC("30000"),
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(20)
          });

          // buyer 3 has principal of 60K USDC with token id: 620
          // await pool.connect(_buyer3).buyProtection({
          //   lendingPoolAddress: lendingPoolAddress,
          //   nftLpTokenId: 620,
          //   protectionAmount: parseUSDC("40000"),
          //   protectionExpirationTimestamp: await getUnixTimestampAheadByDays(25)
          // });

          // 190K USDC = 100K + 20K + 30K + 40K
          expect(await pool.totalProtection()).to.eq(parseUSDC("150000"));
          expect(await pool.getAllProtections()).to.have.lengthOf(3);

          await moveForwardTimeByDays(31);
          // pay to lending pool
          await payToLendingPoolAddress(lendingPoolAddress, "100000", USDC);

          // 2nd & 3rd protections should be expired and removed
          await pool.accruePremiumAndExpireProtections();

          expect(await pool.getAllProtections()).to.have.lengthOf(2);
          expect(await pool.totalProtection()).to.eq(parseUSDC("140000")); // 140K USDC = 100K + 40K
        });

        // This test is meant to report gas usage for buyProtection with large numbers of protections in the pool
        xit("...gas consumption test", async () => {
          const gasUsage = [];

          // buyer 0x4535498cfbee9c7e2f817d1df21b2e9e2d9ec9b4 has principal of 25K USDC with token id: 575
          const buyer1 = await ethers.getImpersonatedSigner(
            "0x4535498cfbee9c7e2f817d1df21b2e9e2d9ec9b4"
          );

          for (let index = 0; index < 151; index++) {
            const tx = await pool.connect(buyer1).buyProtection(
              {
                lendingPoolAddress: lendingPoolAddress,
                nftLpTokenId: 575,
                protectionAmount: parseUSDC("10000"),
                protectionExpirationTimestamp:
                  await getUnixTimestampAheadByDays(30)
              },
              { gasLimit: 10_000_000 } // 30_000_000 is block gas limit
            );
            const receipt = await tx.wait();

            console.log(
              `Gas used for protection# ${
                index + 1
              }: ${receipt.gasUsed.toString()}`
            );
            gasUsage.push(`${receipt.gasUsed}`);
            // console.log(`***** Buy Protection ${index}`);
          }
          console.log(`***** buyProtection Gas Usage: ${gasUsage.join("\n")}`);
        });

        // This test is meant to report gas usage for deposit with large numbers of protections in the pool
        xit("...gas consumption test for deposit", async () => {
          const gasUsage = [];
          // Revert the state of the pool to the open state
          expect(
            await network.provider.send("evm_revert", [
              before1stDepositSnapshotId
            ])
          ).to.eq(true);
          console.log(
            "***** Current Pool Cycle State: " +
              (await poolCycleManager.getCurrentCycleState(poolInfo.poolId))
          );

          // buyer 0x4535498cfbee9c7e2f817d1df21b2e9e2d9ec9b4 has principal of 25K USDC with token id: 575
          const buyer1 = await ethers.getImpersonatedSigner(
            "0x4535498cfbee9c7e2f817d1df21b2e9e2d9ec9b4"
          );

          // Approve the pool to spend USDC
          await USDC.approve(pool.address, parseUSDC("1000000"));
          for (let index = 0; index < 150; index++) {
            await pool.connect(buyer1).buyProtection(
              {
                lendingPoolAddress: lendingPoolAddress,
                nftLpTokenId: 575,
                protectionAmount: parseUSDC("10000"),
                protectionExpirationTimestamp:
                  await getUnixTimestampAheadByDays(60)
              },
              { gasLimit: 10_000_000 } // 30_000_000 is block gas limit
            );
            const tx = await pool.deposit(parseUSDC("1000"), deployerAddress, {
              gasLimit: 10_000_000
            }); // 30_000_000 is block gas limit
            const receipt = await tx.wait();

            console.log(
              `Gas used for deposit after protection# ${
                index + 1
              }: ${receipt.gasUsed.toString()}`
            );
            gasUsage.push(`${receipt.gasUsed}`);
            console.log(`***** Buy Protection + Deposit ${index}`);
          }
          console.log(`***** deposit Gas Usage: \n ${gasUsage.join("\n")}`);
        });
      });

      describe("buyProtection after deposit", async () => {
        it("...should succeed when total protection is higher than min requirement and leverage ratio higher than floor", async () => {
          // Approve the pool to spend USDC & deposit 5K USDC, min capital required is 5K
          const _depositAmount = parseUSDC("5000");
          await transferAndApproveUsdc(deployer, _depositAmount);
          await pool.connect(deployer).deposit(_depositAmount, deployerAddress);

          // Buyer 1 buys protection of 10K USDC, so approve premium to be paid
          await transferAndApproveUsdc(_protectionBuyer1, parseUSDC("500"));
          await pool.connect(_protectionBuyer1).buyProtection({
            lendingPoolAddress: lendingPoolAddress,
            // see: https://lark.market/tokenDetail?tokenId=590
            nftLpTokenId: 590, // this token has 420K principal for buyer 1
            protectionAmount: parseUSDC("10000"),
            protectionExpirationTimestamp: getUnixTimestampAheadByDays(15)
          });

          expect(await pool.getAllProtections()).to.have.lengthOf(2);
          expect(await pool.totalProtection()).to.eq(parseUSDC("110000")); // 100K + 10K

          // previous deposits: 3K + 3K + 20 = 6020, new deposit: 5K
          expect(await calculateTotalSellerDeposit()).to.eq(parseUSDC("11020"));
        });
      });

      const currentPoolCycleIndex = 0;

      describe("...before 1st pool cycle is locked", async () => {
        before(async () => {
          // Revert the state of the pool before 1st deposit
          expect(
            await network.provider.send("evm_revert", [
              before1stDepositSnapshotId
            ])
          ).to.eq(true);
          console.log(
            "Pool capital: ",
            await poolInstance.totalSTokenUnderlying()
          );
          beforePoolCycleTestSnapshotId = await network.provider.send(
            "evm_snapshot",
            []
          );
        });

        it("...pool cycle should be in open state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 1); // 1 = Open
        });

        it("...can create withdrawal requests", async () => {
          // create withdrawal requests (cycle after next: 2)

          // Seller1: deposit 2000 USDC & request withdrawal of 1000 sTokens
          const _depositAmount1 = parseUSDC("2000");
          await depositAndRequestWithdrawal(
            seller,
            sellerAddress,
            _depositAmount1,
            parseEther("1000")
          );

          // Seller2: deposit 10000 USDC & request withdrawal of 1000 sTokens
          const _depositAmount2 = parseUSDC("2000");
          await depositAndRequestWithdrawal(
            owner,
            ownerAddress,
            _depositAmount2,
            parseEther("1000")
          );

          // Seller3: deposit 2000 USDC & request withdrawal of 1000 sTokens
          const _depositAmount3 = parseUSDC("3000");
          await depositAndRequestWithdrawal(
            account4,
            account4Address,
            _depositAmount3,
            parseEther("1000")
          );
        });

        it("...can buy protection", async () => {
          await USDC.connect(_protectionBuyer1).approve(
            pool.address,
            parseUSDC("3000")
          );
          await pool.connect(_protectionBuyer1).buyProtection({
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 590,
            protectionAmount: parseUSDC("40000"),
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(20)
          });
        });

        it("...has correct total requested withdrawal & total sToken underlying", async () => {
          const _withdrawalCycleIndex = currentPoolCycleIndex + 2;

          expect(
            await pool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex)
          ).to.eq(parseEther("3000"));

          expect(await pool.totalSTokenUnderlying()).to.be.eq(
            parseUSDC("7000")
          ); // 3 deposits = 2000 + 2000 + 3000
        });
      });

      describe("...1st pool cycle is locked", async () => {
        before(async () => {
          // Move pool cycle(open period: 10 days, total duration: 30 days) past 10 days to locked state
          await moveForwardTimeByDays(11);
        });

        it("...pool cycle should be in locked state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 2); // 2 = Locked
        });

        it("...deposit should succeed", async () => {
          const _underlyingAmount = parseUSDC("100");

          await transferAndApproveUsdc(seller, _underlyingAmount);
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
      describe("...open period but no withdrawal", async () => {
        before(async () => {
          // Move pool cycle(10 days open period, 30 days total duration) to open state of 2nd cycle
          await moveForwardTimeByDays(20);
        });

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
          await moveForwardTimeByDays(11);
        });

        it("...pool cycle should be in locked state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 2); // 2 = Locked
        });

        it("...deposit should succeed", async () => {
          const _underlyingAmount = parseUSDC("100");

          await transferAndApproveUsdc(seller, _underlyingAmount);
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
          // Seller1: deposited 2000 USDC in 1st cycle & requested to withdraw 1000. Now request withdrawal of 1000 sTokens
          await pool.connect(seller).requestWithdrawal(parseEther("1000"));
          // Seller2: deposited 3000 USDC in 1st cycle & requested to withdraw 1000, now request withdrawal of 2000 sTokens
          await pool.connect(owner).requestWithdrawal(parseEther("2000"));
          // Seller3: deposited 2000 USDC in 1st cycle & requested to withdraw 1000, now request withdrawal of 1000 sTokens
          await pool.connect(account4).requestWithdrawal(parseEther("1000"));
        });

        it("...has correct total requested withdrawal", async () => {
          const _withdrawalCycleIndex = currentPoolCycleIndex + 2;

          expect(
            await pool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex)
          ).to.eq(parseEther("4000"));
        });
      });
    });

    describe("...3rd pool cycle", async () => {
      const currentPoolCycleIndex = 2;

      describe("...open period with withdrawal", async () => {
        before(async () => {
          // Move pool cycle(10 days open period, 30 days total duration) to open state (next pool cycle)
          await moveForwardTimeByDays(20);
        });

        it("...pool cycle should be in open state", async () => {
          await verifyPoolState(currentPoolCycleIndex, 1); // 1 = Open
        });

        it("...has correct total requested withdrawal amount", async () => {
          expect(
            await pool.getTotalRequestedWithdrawalAmount(currentPoolCycleIndex)
          ).to.eq(parseEther("3000"));

          expect(await pool.totalSTokenUnderlying()).to.be.eq(
            parseUSDC("7200")
          ); // 5 deposits = 2000 + 2000 + 3000 + 100 + 100
        });

        it("...fails when withdrawal amount is higher than requested amount", async () => {
          // Seller has requested 1000 sTokens in 1st cycle
          const withdrawalAmt = parseEther("1001");
          await expect(
            pool.connect(seller).withdraw(withdrawalAmt, sellerAddress)
          ).to.be.revertedWith(
            `WithdrawalHigherThanRequested("${sellerAddress}", ${parseEther(
              "1000"
            ).toString()})`
          );
        });

        it("...is successful for 1st seller", async () => {
          // Seller has requested 1000 sTokens in previous cycle
          const withdrawalAmt = parseEther("1000");
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
          // 2nd seller (Owner account) has requested 1000 sTokens in 1st cycle
          const withdrawalAmt = parseEther("1000");
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
          // 3rd seller (Account4) has requested total 1000 sTokens in 1st cycle,
          // so partial withdrawal should be possible
          await verifyWithdrawal(account4, parseEther("600"));
          await verifyWithdrawal(account4, parseEther("300"));
        });

        it("...fails for third withdrawal by 3rd seller", async () => {
          // 3rd Seller(account4) has withdrawn 900 out of 100 requested tokens,
          // so withdrawal request should exist with 100 sTokens remaining
          expect(
            await pool
              .connect(account4)
              .getRequestedWithdrawalAmount(currentPoolCycleIndex)
          ).to.eq(parseEther("100"));
          // withdrawing more(101) sTokens than remaining requested should fail
          await expect(
            pool.connect(account4).withdraw(parseEther("101"), account4Address)
          ).to.be.revertedWith(
            `WithdrawalHigherThanRequested("${account4Address}", ${parseEther(
              "100"
            )})`
          );
        });
      });
    });

    describe("buyProtection failures with time restrictions", async () => {
      it("...fails when lending pool is late for payment", async () => {
        // time has moved forward by more than 30 days, so lending pool is late for payment
        await expect(
          pool.connect(_protectionBuyer1).buyProtection({
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 590,
            protectionAmount: parseUSDC("101"),
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(20)
          })
        ).to.be.revertedWith(
          `LendingPoolHasLatePayment("0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf")`
        );
      });
    });

    describe("claimUnlockedCapital", async () => {
      let lendingPool: ITranchedPool;
      let _totalSTokenUnderlying: BigNumber;

      const getLatestLockedCapital = async () => {
        return (
          await defaultStateManager.getLockedCapitals(
            poolInstance.address,
            lendingPoolAddress
          )
        )[0];
      };

      async function claimAndVerifyUnlockedCapital(
        account: Signer,
        success: boolean
      ): Promise<BigNumber> {
        const _address = await account.getAddress();
        const _expectedBalance = (await poolInstance.balanceOf(_address))
          .mul(_totalSTokenUnderlying)
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
        lendingPool = (await ethers.getContractAt(
          "ITranchedPool",
          lendingPoolAddress
        )) as ITranchedPool;

        _totalSTokenUnderlying = await poolInstance.totalSTokenUnderlying();
      });

      it("...should have locked capital after missing a payment", async () => {
        // time has moved forward by more than 30 days, so lending pool is late for payment
        // and state should be transitioned to "Late" and capital should be locked
        await expect(defaultStateManager.assessStates())
          .to.emit(defaultStateManager, "PoolStatesAssessed")
          .to.emit(defaultStateManager, "LendingPoolLocked");

        // verify that lending pool capital is locked
        const _lockedCapital = await getLatestLockedCapital();
        expect(_lockedCapital.locked).to.be.true;

        // verify that locked capital is total underlying capital
        expect(_lockedCapital.amount).to.be.eq(_totalSTokenUnderlying);
      });

      it("...should have unlocked capital after payment", async () => {
        await payToLendingPool(
          lendingPool,
          "1000000",
          getUsdcContract(deployer)
        );
        await expect(defaultStateManager.assessStates())
          .to.emit(defaultStateManager, "PoolStatesAssessed")
          .to.emit(defaultStateManager, "LendingPoolUnlocked");

        // verify that lending pool capital is unlocked
        const _lockedCapital = await getLatestLockedCapital();
        expect(_lockedCapital.locked).to.be.false;

        // verify that unlocked capital is total underlying capital
        expect(_lockedCapital.amount).to.be.eq(_totalSTokenUnderlying);
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
        expect(await claimAndVerifyUnlockedCapital(seller, false)).to.be.eq(0);
      });

      it("...owner should be  able to claim his share of unlocked capital from pool 1", async () => {
        expect(await claimAndVerifyUnlockedCapital(owner, true)).to.be.gt(0);
      });

      it("...owner should  NOT be able to claim again", async () => {
        expect(await claimAndVerifyUnlockedCapital(owner, false)).to.be.eq(0);
      });

      it("...account 4 should be  able to claim his share of unlocked capital from pool 1", async () => {
        expect(await claimAndVerifyUnlockedCapital(account4, true)).to.be.gt(0);
      });

      it("...account 4 should  NOT be able to claim again", async () => {
        expect(await claimAndVerifyUnlockedCapital(account4, false)).to.be.eq(
          0
        );
      });
    });

    describe("buyProtection fails because of protection purchase limit", async () => {
      it("...should fail", async () => {
        // lending pool payment is current, so buyProtection should NOT fail for late payment,
        // but it should fail because of protection purchase limit: past 60 days
        await expect(
          pool.connect(_protectionBuyer1).buyProtection({
            lendingPoolAddress: lendingPoolAddress,
            nftLpTokenId: 590,
            protectionAmount: parseUSDC("101"),
            protectionExpirationTimestamp: await getUnixTimestampAheadByDays(11)
          })
        ).to.be.revertedWith("ProtectionPurchaseNotAllowed");
      });
    });

    after(async () => {
      // Revert the EVM state before pool cycle tests in "before 1st pool cycle is locked"
      // to revert the time forwarded in the tests
      expect(
        await network.provider.send("evm_revert", [
          beforePoolCycleTestSnapshotId
        ])
      ).to.be.eq(true);
    });
  });
};

export { testPool };
