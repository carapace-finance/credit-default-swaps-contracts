import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ethers, network } from "hardhat";
import { parseEther } from "ethers/lib/utils";
import {
  CIRCLE_ACCOUNT_ADDRESS,
  USDC_ADDRESS,
  USDC_DECIMALS,
  USDC_ABI
} from "../utils/constants";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { PremiumPricing } from "../../typechain-types/contracts/core/PremiumPricing";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import {
  getUnixTimestampOfSomeMonthAhead,
  getUnixTimestampAheadByDays,
  getDaysInSeconds,
  getLatestBlockTimestamp,
  moveForwardTime
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
    let buyerAddress: string;
    let ownerAddress: string;
    let USDC: Contract;
    let poolInfo: any;
    let poolCycleManager: PoolCycleManager;
    let premiumPricing: PremiumPricing;
    let referenceLendingPools: ReferenceLendingPools;
    let snapshotId: string;

    before("setup", async () => {
      deployerAddress = await deployer.getAddress();
      sellerAddress = await seller.getAddress();
      buyerAddress = await buyer.getAddress();
      ownerAddress = await owner.getAddress();

      poolInfo = await pool.poolInfo();

      USDC = await new Contract(USDC_ADDRESS, USDC_ABI, deployer);

      // Impersonate CIRCLE account and transfer some USDC to deployer to test with
      const circleAccount = await ethers.getImpersonatedSigner(
        CIRCLE_ACCOUNT_ADDRESS
      );
      USDC.connect(circleAccount).transfer(
        deployerAddress,
        BigNumber.from(1000000).mul(USDC_DECIMALS)
      );
      USDC.connect(circleAccount).transfer(
        ownerAddress,
        BigNumber.from(1000).mul(USDC_DECIMALS)
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
        expect(poolInfo.params.minRequiredCapital).to.eq(parseUSDC("50000"));
      });
      it("...set the min required protection", async () => {
        expect(poolInfo.params.minRequiredProtection).to.eq(
          parseUSDC("100000")
        );
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

    describe("calculateLeverageRatio without any protection buyers or sellers", () => {
      it("...should return 0 when pool has no protection sold", async () => {
        expect(await pool.calculateLeverageRatio()).to.equal(0);
      });
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

      it("...reentrancy should fail", async () => {});

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
          .emit(pool, "PremiumAccrued")
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
        expect(await pool.totalProtection()).to.eq(_protectionAmount);
      });

      it("...the buyer account for the msg.sender exists already", async () => {
        const _noBuyerAccountExist: boolean =
          (await pool
            .ownerAddressToBuyerAccountId(deployerAddress)
            .toString()) === "0";
        expect(_noBuyerAccountExist).to.eq(false);
      });

      it("...fail when total protection crosses min requirement with leverage ratio breaching floor", async () => {
        const _expirationTime: BigNumber = getUnixTimestampAheadByDays(30);
        const _protectionAmount = parseUSDC("100000");

        await USDC.approve(pool.address, _protectionAmount);

        await expect(
          pool.buyProtection(1, _expirationTime, _protectionAmount)
        ).to.be.revertedWith("PoolLeverageRatioTooLow(1, 2236363636)");
      });
    });

    describe("calculateLeverageRatio after 1st protection", () => {
      it("...should return 0 when pool has no protection sellers", async () => {
        expect(await pool.calculateLeverageRatio()).to.equal(0);
      });
    });

    describe("...deposit", async () => {
      const _underlyingAmount: BigNumber = parseUSDC("10");
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

      it("...fail if pool is paused", async () => {
        snapshotId = await network.provider.send("evm_snapshot", []);

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

      it("...reentrancy should fail", async () => {});

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

      it("...fail if deposit causes to breach leverage ratio ceiling", async () => {
        expect(await pool.totalProtection()).to.eq(parseUSDC("10000"));

        const depositAmt: BigNumber = parseUSDC("52000");

        await expect(
          pool.deposit(depositAmt, sellerAddress)
        ).to.be.revertedWith("PoolLeverageRatioTooHigh");
      });

      it("...2nd deposit is successful", async () => {
        await expect(pool.deposit(_underlyingAmount, sellerAddress))
          .to.emit(pool, "PremiumAccrued")
          .to.emit(pool, "ProtectionSold")
          .withArgs(sellerAddress, _underlyingAmount);

        // 2nd deposit will receive less sTokens shares than the first deposit because of the premium accrued
        expect(await pool.connect(seller).balanceOf(sellerAddress))
          .to.be.gt(parseEther("19.999"))
          .and.lt(parseEther("20"));
      });

      it("...should return 20 USDC as total seller deposit", async () => {
        // sTokens balance of seller should be same as underlying deposit amount
        expect(await pool.totalSellerDeposit()).to.eq(_underlyingAmount.mul(2));
      });

      it("...should convert sToken shares to correct underlying amount", async () => {
        const convertedUnderlying = await pool.convertToUnderlying(
          await pool.connect(seller).balanceOf(sellerAddress)
        );

        // Seller should receive little bit more USDC amt than deposited because of accrued premium
        expect(convertedUnderlying)
          .to.be.gt(parseUSDC("19.9877"))
          .and.lt(parseUSDC("20.1"));
      });
    });

    describe("calculateLeverageRatio after 1 protection & 2 deposits", () => {
      it("...should return correct leverage ratio", async () => {
        expect(await pool.calculateLeverageRatio())
          .to.be.gt(parseEther("0.002"))
          .and.lt(parseEther("0.0021"));
      });
    });

    describe("...requestWithdrawal", async () => {
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
        ).to.be.revertedWith(`InsufficientSTokenBalance("${buyerAddress}", 0)`);
      });

      it("...fail when withdrawal amount is higher than token balance", async () => {
        const _tokenAmt = parseEther("21");
        const _tokenBalance = await pool.balanceOf(sellerAddress);
        await expect(
          pool.connect(seller).requestWithdrawal(_tokenAmt)
        ).to.be.revertedWith(
          `InsufficientSTokenBalance("${sellerAddress}", ${_tokenBalance})`
        );
      });

      it("...1st request is successful", async () => {
        const _tokenAmt = parseEther("11");
        const _minPoolCycleIndex = 1;
        await expect(pool.connect(seller).requestWithdrawal(_tokenAmt))
          .to.emit(pool, "WithdrawalRequested")
          .withArgs(sellerAddress, _tokenAmt, _minPoolCycleIndex);

        const request = await pool.withdrawalRequests(sellerAddress);
        expect(request.sTokenAmount).to.eq(_tokenAmt);
        expect(request.minPoolCycleIndex).to.eq(_minPoolCycleIndex);
      });

      it("...2nd request by same user should update existing request", async () => {
        const _tokenAmt = parseEther("5");
        const _minPoolCycleIndex = 1;
        await expect(pool.connect(seller).requestWithdrawal(_tokenAmt))
          .to.emit(pool, "WithdrawalRequested")
          .withArgs(sellerAddress, _tokenAmt, _minPoolCycleIndex);

        const request = await pool.withdrawalRequests(sellerAddress);
        expect(request.sTokenAmount).to.eq(_tokenAmt);
        expect(request.minPoolCycleIndex).to.eq(1);
      });

      it("...fail when amount in updating request is higher than token balance", async () => {
        const _tokenAmt = parseEther("21");
        const _tokenBalance = await pool.balanceOf(sellerAddress);
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

        const _minPoolCycleIndex = 1;
        const _tokenBalance = await pool.balanceOf(ownerAddress);
        await expect(pool.connect(owner).requestWithdrawal(_tokenBalance))
          .to.emit(pool, "WithdrawalRequested")
          .withArgs(ownerAddress, _tokenBalance, _minPoolCycleIndex);

        const request = await pool.withdrawalRequests(ownerAddress);
        expect(request.sTokenAmount).to.eq(_tokenBalance);
        expect(request.minPoolCycleIndex).to.eq(_minPoolCycleIndex);
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

    describe("accruePremium", async () => {
      it("...should accrue premium and update last accrual timestamp", async () => {
        const totalPremiumAccruedBefore = await pool.totalPremiumAccrued();
        await expect(pool.accruePremium()).to.emit(pool, "PremiumAccrued");

        expect(await pool.totalPremiumAccrued()).to.be.gt(
          totalPremiumAccruedBefore
        );
        expect(await pool.lastPremiumAccrualTimestamp()).to.eq(
          await getLatestBlockTimestamp()
        );
      });

      it("...should remove single expired protection", async () => {
        const protectionCount = (await pool.getAllProtections()).length;
        expect(protectionCount).to.eq(1);
        expect(await pool.totalProtection()).to.eq(parseUSDC("10000"));
        await pool.buyProtection(
          BigNumber.from(1),
          getUnixTimestampOfSomeMonthAhead(1),
          parseUSDC("20000")
        );
        expect(await pool.totalProtection()).to.eq(parseUSDC("30000"));
        expect(await pool.getAllProtections()).to.have.lengthOf(2);

        // move forward time by 31 days
        await moveForwardTime(BigNumber.from(31 * 24 * 60 * 60));

        // 2nd protection should be expired and removed
        await pool.accruePremium();
        expect(await pool.getAllProtections()).to.have.lengthOf(1);
        expect(await pool.totalProtection()).to.eq(parseUSDC("10000"));

        // all premium for expired protection should be accrued
        expect(await pool.totalPremiumAccrued()).to.be.gt(parseUSDC("2000"));
      });

      it("...should remove multiple expired protection", async () => {
        const protectionCount = (await pool.getAllProtections()).length;
        expect(protectionCount).to.eq(1);
        expect(await pool.totalProtection()).to.eq(parseUSDC("10000"));

        // add bunch of protections
        await pool.buyProtection(
          BigNumber.from(2),
          await getUnixTimestampAheadByDays(10),
          parseUSDC("20000")
        );

        await pool.buyProtection(
          BigNumber.from(1),
          await getUnixTimestampAheadByDays(20),
          parseUSDC("30000")
        );

        await pool.buyProtection(
          BigNumber.from(1),
          await getUnixTimestampAheadByDays(30),
          parseUSDC("40000")
        );

        expect(await pool.totalProtection()).to.eq(parseUSDC("100000")); // 100K USDC
        expect(await pool.getAllProtections()).to.have.lengthOf(4);

        // move forward time by 21 days
        await moveForwardTime(BigNumber.from(21 * 24 * 60 * 60));

        // 2nd & 3rd protections should be expired and removed
        await pool.accruePremium();
        expect(await pool.getAllProtections()).to.have.lengthOf(2);
        expect(await pool.totalProtection()).to.eq(parseUSDC("50000"));
      });

      // This test is meant to report gas usage for buyProtection with large numbers of protections in the pool
      xit("...gas consumption test", async () => {
        const gasUsage = [];
        for (let index = 0; index < 151; index++) {
          const tx = await pool.buyProtection(
            BigNumber.from(1),
            getUnixTimestampOfSomeMonthAhead(3),
            parseUSDC("10000"),
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
        await network.provider.send("evm_revert", [snapshotId]);

        console.log(
          "***** Current Pool Cycle State: " +
            (await poolCycleManager.getCurrentCycleState(poolInfo.poolId))
        );

        // Approve the pool to spend USDC
        await USDC.approve(pool.address, parseUSDC("1000000"));

        for (let index = 0; index < 150; index++) {
          await pool.buyProtection(
            BigNumber.from(1),
            getUnixTimestampOfSomeMonthAhead(6),
            parseUSDC("10000"),
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
        const _expirationTime: BigNumber = getUnixTimestampAheadByDays(30);
        const _protectionAmount = parseUSDC("10000");
        const _underlyingAmount = parseUSDC("1000");

        // Revert the state of the pool to the open state
        await network.provider.send("evm_revert", [snapshotId]);

        await USDC.approve(
          pool.address,
          _underlyingAmount.add(_protectionAmount)
        );

        await pool.deposit(_underlyingAmount, sellerAddress);
        await pool.buyProtection(1, _expirationTime, _protectionAmount);

        expect(await pool.getAllProtections()).to.have.lengthOf(2);
        expect(await pool.totalProtection()).to.eq(parseUSDC("20000"));

        // state is reverted to just before 1st deposit, so we we can't count previous deposits
        expect(await pool.totalSellerDeposit()).to.eq(parseUSDC("1000"));
      });
    });

    describe("...deposit after pool cycle is locked", async () => {
      it("...should fail", async () => {
        await moveForwardTime(getDaysInSeconds(11));

        // pool cycle should be in locked state
        await expect(
          pool.deposit(parseUSDC("1"), sellerAddress)
        ).to.be.revertedWith(`PoolIsNotOpen(${poolInfo.poolId})`);
      });
    });
  });
};

export { testPool };
