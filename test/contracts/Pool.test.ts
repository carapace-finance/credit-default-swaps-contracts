import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { parseEther, formatEther } from "ethers/lib/utils";
import {
  CIRCLE_ACCOUNT_ADDRESS,
  USDC_ADDRESS,
  USDC_DECIMALS,
  USDC_ABI
} from "../utils/constants";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ethers } from "hardhat";
import { PremiumPricing } from "../../typechain-types/contracts/core/PremiumPricing";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import {
  getUnixTimestampOfSomeMonthAhead,
  getDaysInSeconds,
  getLatestBlockTimestamp
} from "../utils/time";
import { parseUSDC } from "../utils/usdc";

const testPool: Function = (
  deployer: Signer,
  owner: Signer,
  buyer: Signer,
  seller: Signer,
  pool: Pool
) => {
  describe("Pool", () => {
    const _newFloor: BigNumber = BigNumber.from(100);
    const _newCeiling: BigNumber = BigNumber.from(500);
    let deployerAddress: string;
    let sellerAddress: string;
    let USDC: Contract;
    let poolInfo: any;
    let poolCycleManager: PoolCycleManager;
    let premiumPricing: PremiumPricing;
    let referenceLendingPools: ReferenceLendingPools;

    before("setup", async () => {
      deployerAddress = await deployer.getAddress();
      sellerAddress = await seller.getAddress();

      poolInfo = await pool.poolInfo();

      USDC = await new Contract(USDC_ADDRESS, USDC_ABI, deployer);

      // Impersonate CIRCLE account and transfer some USDC to deployer to test with
      const circleAccount = await ethers.getImpersonatedSigner(
        CIRCLE_ACCOUNT_ADDRESS
      );
      USDC.connect(circleAccount).transfer(
        deployerAddress,
        BigNumber.from(10000).mul(USDC_DECIMALS)
      );

      poolCycleManager = (await ethers.getContractAt(
        "PoolCycleManager",
        await pool.poolCycleManager()
      )) as PoolCycleManager;

      premiumPricing = (await ethers.getContractAt(
        "PremiumPricing",
        await pool.premiumPricing()
      )) as PremiumPricing;

      referenceLendingPools = (await ethers.getContractAt(
        "ReferenceLendingPools",
        poolInfo.referenceLendingPools
      )) as ReferenceLendingPools;
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
        expect(poolInfo.params.minRequiredCapital).to.eq(parseEther("100000"));
      });
      it("...set the curvature", async () => {
        expect(poolInfo.params.curvature).to.eq(parseEther("0.05"));
      });
      it("...set the underlying token", async () => {
        expect(poolInfo.underlyingToken.toString()).to.eq(USDC_ADDRESS);
      });
      it("...set the reference loans", async () => {
        expect(poolInfo.referenceLendingPools.toString()).to.eq(
          referenceLendingPools.address
        );
      });
      it("...set the premium pricing contract address", async () => {
        const _premiumPricingAddress: string = await pool.premiumPricing();
        expect(_premiumPricingAddress).to.eq(premiumPricing.address);
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

    describe("calculateLeverageRatio", () => {
      it("...should return 0 when pool has no protection sold", async () => {
        expect(await pool.calculateLeverageRatio()).to.equal(0);
      });

      // xit("...should return correct ratio when tranche has at least 1 protection bought & sold", async () => {
      //   const tranche: Tranche = (await ethers.getContractAt(
      //     "Tranche",
      //     await pool.tranche()
      //   )) as Tranche;
      //   let expirationTime: BigNumber = getUnixTimestampOfSomeMonthAhead(4);
      //   let protectionAmount = BigNumber.from(100000).mul(USDC_DECIMALS); // 100K USDC

      //   await USDC.approve(
      //     pool.address,
      //     BigNumber.from(20000).mul(USDC_DECIMALS)
      //   ); // 20K USDC
      //   await tranche
      //     .connect(account1)
      //     .buyProtection(0, expirationTime, protectionAmount);

      //   // await pool.connect(account1).sellProtection(BigNumber.from(10000).mul(USDC_DECIMALS), await account1.getAddress(), expirationTime);

      //   // Leverage ratio should be little bit higher than 0.1 (scaled by 10^18) because of accrued premium
      //   expect(await pool.calculateLeverageRatio()).to.be.gt(parseEther("0.1"));
      //   expect(await pool.calculateLeverageRatio()).to.be.lt(
      //     parseEther("0.101")
      //   );
      // });
    });

    describe("buyProtection", () => {
      let _protectionAmount: BigNumber;

      it("...should expire the referenceLendingPools", async () => {
        //   await referenceLendingPools.setIsExpired(true);
        //   const _checkIsExpired: boolean =
        //     await referenceLendingPools.checkIsExpired();
        //   expect(_checkIsExpired.toString()).to.eq("true");
      });

      it("...fails if the lending pool has expired already", async () => {
        // await expect(pool.buyProtection(0,0,0)).to.be.revertedWith("Lending pool has expired");
      });

      it("...should roll back the expiration the referenceLendingPools for testing", async () => {
        //   await referenceLendingPools.setIsExpired(true);
        //   const _checkIsExpired: boolean =
        //     await referenceLendingPools.checkIsExpired();
        //   expect(_checkIsExpired.toString()).to.eq("true");
      });

      it("...fails if the lending pool has defaulted", async () => {
        // even if a pool defaults, there may be more default from other loans in the pool. whenNotDefault should be valid only when all the loans in the lending pool default?
      });

      it("...pause the pool contract", async () => {
        await pool.pause();
        expect(await pool.paused()).to.be.true;
      });

      it("...fails if the pool contract is paused", async () => {
        await expect(pool.buyProtection(0, 0, 0)).to.be.revertedWith(
          "Pausable: paused"
        );
      });

      it("...unpause the pool contract", async () => {
        await pool.unpause();
        expect(await pool.paused()).to.be.false;
      });

      it("...reentrancy should fail", async () => {
      });

      it("...the buyer account doesn't exist for the msg.sender", async () => {
        expect(await pool.ownerAddressToBuyerAccountId(deployerAddress)).to.eq(
          0
        );
      });

      it("...fail if USDC is not approved", async () => {
        _protectionAmount = BigNumber.from(10).mul(USDC_DECIMALS);
        await expect(
          pool.buyProtection(0, 0, _protectionAmount)
        ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
      });

      it("...approve 1000 USDC to be transferred by the Pool contract", async () => {
        expect(
          await USDC.approve(
            pool.address,
            BigNumber.from(1000).mul(USDC_DECIMALS)
          )
        )
          .to.emit(USDC, "Approval")
          .withArgs(
            deployerAddress,
            pool.address,
            BigNumber.from(1000).mul(USDC_DECIMALS)
          );

        const _allowanceAmount: number = await USDC.allowance(
          deployerAddress,
          pool.address
        );
        expect(_allowanceAmount.toString()).to.eq(
          BigNumber.from(1000).mul(USDC_DECIMALS).toString()
        );
      });

      it("...create a new buyer account and buy protection", async () => {
        const _initialBuyerAccountId: BigNumber = BigNumber.from(1);
        const _lendingPoolId: BigNumber = BigNumber.from(0);
        let _expirationTime: BigNumber = getUnixTimestampOfSomeMonthAhead(3);
        _protectionAmount = BigNumber.from(10000).mul(USDC_DECIMALS);

        const _premiumAmount: BigNumber = await premiumPricing.calculatePremium(
          _expirationTime,
          _protectionAmount
        );

        const _initialPremiumAmountOfAccount: BigNumber = BigNumber.from(0);
        const _premiumTotalOfLendingPoolIdBefore: BigNumber =
          await pool.lendingPoolIdToPremiumTotal(_lendingPoolId);
        const _premiumTotalBefore: BigNumber = await pool.totalPremium();

        expect(
          await pool.buyProtection(
            _lendingPoolId,
            _expirationTime,
            _protectionAmount
          )
        )
          .to.emit(pool, "BuyerAccountCreated")
          .withArgs(deployerAddress, _initialBuyerAccountId)
          .to.emit(pool, "CoverageBought")
          .withArgs(deployerAddress, _lendingPoolId, _premiumAmount);

        const _premiumAmountOfAccountAfter: BigNumber =
          await pool.buyerAccounts(_initialBuyerAccountId, _lendingPoolId);
        const _premiumTotalOfLendingPoolIdAfter: BigNumber =
          await pool.lendingPoolIdToPremiumTotal(_lendingPoolId);
        const _premiumTotalAfter: BigNumber = await pool.totalPremium();

        expect(_initialPremiumAmountOfAccount.add(_premiumAmount)).to.eq(
          _premiumAmountOfAccountAfter
        );
        expect(_premiumTotalBefore.add(_premiumAmount)).to.eq(
          _premiumTotalAfter
        );
        expect(_premiumTotalOfLendingPoolIdBefore.add(_premiumAmount)).to.eq(
          _premiumTotalOfLendingPoolIdAfter
        );
        expect(await pool.getTotalProtection()).to.eq(_protectionAmount);
      });

      it("...the buyer account for the msg.sender exists already", async () => {
        const _noBuyerAccountExist: boolean =
          (await pool
            .ownerAddressToBuyerAccountId(deployerAddress)
            .toString()) === "0";
        expect(_noBuyerAccountExist).to.eq(false);
      });
    });

    describe("...deposit", async () => {
      const _underlyingAmount: BigNumber =
        BigNumber.from(10).mul(USDC_DECIMALS);
      const _exceededAmount: BigNumber =
        BigNumber.from(100000000).mul(USDC_DECIMALS);
      const _shortExpirationTime: BigNumber =
        getUnixTimestampOfSomeMonthAhead(2);
      const _zeroAddress: string = "0x0000000000000000000000000000000000000000";

      it("...approve 0 USDC to be transferred by the Pool contract", async () => {
        expect(
          await USDC.approve(pool.address, BigNumber.from(0).mul(USDC_DECIMALS))
        )
          .to.emit(USDC, "Approval")
          .withArgs(
            deployerAddress,
            pool.address,
            BigNumber.from(0).mul(USDC_DECIMALS)
          );

        const _allowanceAmount: number = await USDC.allowance(
          deployerAddress,
          pool.address
        );
        expect(_allowanceAmount.toString()).to.eq(
          BigNumber.from(0).mul(USDC_DECIMALS).toString()
        );
      });

      it("...fail if pool cycle is not open for deposit", async () => {
        await expect(
          pool.deposit(_underlyingAmount, sellerAddress)
        ).to.be.revertedWith(`PoolIsNotOpen(${poolInfo.poolId})`);
      });

      it("...fail if pool is paused", async () => {
        // register the pool with pool cycle manager to open the pool cycle
        await poolCycleManager
          .connect(deployer)
          .registerPool(
            poolInfo.poolId,
            getDaysInSeconds(10),
            getDaysInSeconds(20)
          );

        expect(
          await poolCycleManager.getCurrentCycleState(poolInfo.poolId)
        ).to.equal(1); // 1 = Open

        // pause the pool
        await pool.connect(deployer).pause();
        expect(await pool.paused()).to.be.true;

        await expect(
          pool.deposit(_underlyingAmount, sellerAddress)
        ).to.be.revertedWith("Pausable: paused");
      });

      it("...unpause the Pool contract", async () => {
        await pool.unpause();
        expect(await pool.paused()).to.be.false;
      });

      it("...fail if USDC is not approved", async () => {
        await expect(
          pool.deposit(_underlyingAmount, sellerAddress)
        ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
      });

      it("...approve 100000000 USDC to be transferred by the Pool contract", async () => {
        expect(
          await USDC.approve(
            pool.address,
            BigNumber.from(100000000).mul(USDC_DECIMALS)
          )
        )
          .to.emit(USDC, "Approval")
          .withArgs(
            deployerAddress,
            pool.address,
            BigNumber.from(100000000).mul(USDC_DECIMALS)
          );

        const _allowanceAmount: number = await USDC.allowance(
          deployerAddress,
          pool.address
        );
        expect(_allowanceAmount.toString()).to.eq(
          BigNumber.from(100000000).mul(USDC_DECIMALS).toString()
        );
      });

      it("...fail if an SToken receiver is a zero address", async () => {
        await expect(
          pool.deposit(_underlyingAmount, _zeroAddress)
        ).to.be.revertedWith("ERC20: mint to the zero address");
      });

      it("...reentrancy should fail", async () => {
      });

      it("...is successful", async () => {
        await expect(pool.deposit(_underlyingAmount, sellerAddress))
          .to.emit(pool, "PremiumAccrued")
          .to.emit(pool, "ProtectionSold")
          .withArgs(sellerAddress, _underlyingAmount);
      });

      it("...interest accrued", async () => {
        expect(await pool.lastPremiumAccrualTimestamp()).to.eq(
          await getLatestBlockTimestamp()
        );
        expect(await pool.totalPremiumAccrued()).to.be.gt(0);
      });

      it("...receiver receives 10 sTokens", async () => {
        // sTokens balance of seller should be same as underlying deposit amount
        expect(await pool.connect(seller).balanceOf(sellerAddress)).to.eq(
          parseEther("10")
        );
      });

      it("...should return 10 USDC as total seller deposit", async () => {
        // sTokens balance of seller should be same as underlying deposit amount
        expect(await pool.totalSellerDeposit()).to.eq(_underlyingAmount);
      });

      it("...total capital should be equal to total collateral plus total premium accrued", async () => {
        // sTokens balance of seller should be same as underlying deposit amount
        const totalPremiumAccrued = await pool.totalPremiumAccrued();
        const totalSellerDeposit = await pool.totalSellerDeposit();
        expect(await pool.getTotalCapital()).to.eq(
          totalPremiumAccrued.add(totalSellerDeposit)
        );
      });

      // We have 1000 USDC premium from the protection buyer + 10 USDC from the deposit
      it("...should return 1010 total underlying amount received as premium + deposit", async () => {
        const _totalUnderlying: BigNumber = await USDC.balanceOf(pool.address);
        expect(_totalUnderlying).to.eq(BigNumber.from(1010).mul(USDC_DECIMALS));
      });

      // pool being used inside tranche contract is different than pool passed into this test via deploy.ts
      xit("...fail if deposit causes to breach leverage ratio ceiling", async () => {
        expect(await pool.getTotalProtection()).to.eq(
          BigNumber.from(10000).mul(USDC_DECIMALS)
        );

        const depositAmt: BigNumber = BigNumber.from(2100).mul(USDC_DECIMALS);

        await expect(
          pool.deposit(depositAmt, sellerAddress)
        ).to.be.revertedWith("PoolLeverageRatioTooHigh");
      });

      it("...2nd deposit is successful", async () => {
        await expect(pool.deposit(_underlyingAmount, sellerAddress))
          .to.emit(pool, "PremiumAccrued")
          .to.emit(pool, "ProtectionSold")
          .withArgs(sellerAddress, _underlyingAmount);
        console.log(
          "sToken Balance of seller after 2nd deposit: ",
          formatEther(await pool.connect(seller).balanceOf(sellerAddress))
        );

        // 2nd deposit will receive less sTokens shares than the first deposit because of the premium accrued
        expect(await pool.connect(seller).balanceOf(sellerAddress))
          .to.be.gt(parseEther("19.9877"))
          .and.lt(parseEther("19.9878"));
      });

      it("...should return 20 USDC as total seller deposit", async () => {
        // sTokens balance of seller should be same as underlying deposit amount
        expect(await pool.totalSellerDeposit()).to.eq(_underlyingAmount.mul(2));
      });

      it("... should convert sToken shares to correct underlying amount", async () => {
        const convertedUnderlying = await pool.convertToUnderlying(
          await pool.connect(seller).balanceOf(sellerAddress)
        );

        // Seller should receive little bit more USDC amt than deposited because of accrued premium
        expect(convertedUnderlying)
          .to.be.gt(parseUSDC("19.9877"))
          .and.lt(parseUSDC("20.1"));
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
  });
};

export { testPool };
