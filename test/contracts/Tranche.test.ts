import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { CIRCLE_ACCOUNT_ADDRESS, USDC_ADDRESS, USDC_DECIMALS, USDC_ABI } from "../utils/constants";
import { PremiumPricing } from "../../typechain-types/contracts/core/PremiumPricing";
import { Tranche } from "../../typechain-types/contracts/core/Tranche";
import { getUnixTimestampOfSomeMonthAhead } from "../utils/time";
import { ethers } from "hardhat";

const tranche: Function = (
  deployer: Signer,
  owner: Signer,
  buyer: Signer,
  seller: Signer,
  premiumPricing: PremiumPricing,
  tranche: Tranche
) => {
  describe("Tranche", () => {
    let deployerAddress: string;
    let ownerAddress: string;
    let buyerAddress: string;
    let sellerAddress: string;
    let USDC: Contract;

    before("get addresses", async () => {
      deployerAddress = await deployer.getAddress();
      ownerAddress = await owner.getAddress();
      buyerAddress = await buyer.getAddress();
      sellerAddress = await seller.getAddress();
    });

    before("instantiate USDC token contract and transfer USDC to deployer account", async () => {
      USDC = await new Contract(USDC_ADDRESS, USDC_ABI, deployer);

      // Impersonate CIRCLE account and transfer some USDC to deployer to test with
      const circleAccount = await ethers.getImpersonatedSigner(CIRCLE_ACCOUNT_ADDRESS);
      USDC.connect(circleAccount).transfer(deployerAddress, BigNumber.from(1000).mul(USDC_DECIMALS));
    });

    describe("constructor", () => {
      it("...set the SToken name", async () => {
        const _name: string = await tranche.name();
        expect(_name).to.eq("sToken");
      });
      it("...set the SToken symbol", async () => {
        const _symbol: string = await tranche.symbol();
        // todo: need to come up with a better symbol
        expect(_symbol).to.eq("LPT");
      });
      it("...set the USDC as the underlying token", async () => {
        const _underlyingToken: string = await tranche.underlyingToken();
        expect(_underlyingToken).to.eq(USDC_ADDRESS);
      });
      it("...set the reference lending pool contract address", async () => {
        const _referenceLoansAddress: string = await tranche.referenceLoans();
        // todo: the _referenceLoansAddress should not be USDC_ADDRESS
        expect(_referenceLoansAddress).to.eq(USDC_ADDRESS);
      });
      it("...set the premium pricing contract address", async () => {
        const _premiumPricingAddress: string = await tranche.premiumPricing();
        expect(_premiumPricingAddress).to.eq(premiumPricing.address);
      });
    });

    describe("buyProtection", () => {
      let _protectionAmount: BigNumber;

      it("...should expire the referenceLoans", async () => {
        // todo: write this test once you finish writing the ReferenceLoans contract
        //   await referenceLoans.setIsExpired(true);
        //   const _checkIsExpired: boolean =
        //     await referenceLoans.checkIsExpired();
        //   expect(_checkIsExpired.toString()).to.eq("true");
      });

      it("...fails if the lending pool has expired already", async () => {
        // todo: write this test once you finish writing the ReferenceLoans contract
        // await expect(tranche.buyProtection(0,0,0)).to.be.revertedWith("Lending pool has expired");
      });

      it("...should roll back the expiration the referenceLoans for testing", async () => {
        // todo: write this test once you finish writing the ReferenceLoans contract
        //   await referenceLoans.setIsExpired(true);
        //   const _checkIsExpired: boolean =
        //     await referenceLoans.checkIsExpired();
        //   expect(_checkIsExpired.toString()).to.eq("true");
      });

      it("...fails if the lending pool has defaulted", async () => {
        // todo: write this test once you finish writing the ReferenceLoans contract
        // even if a pool defaults, there may be more default from other loans in the pool. whenNotDefault should be valid only when all the loans in the lending pool default?
      });

      it("...pause the Tranche contract", async () => {
        await tranche.pauseTranche();
        expect(await tranche.paused()).to.be.true;
      });

      it("...fails if the Tranche contract is paused", async () => {
        await expect(tranche.buyProtection(0, 0, 0)).to.be.revertedWith(
          "Pausable: paused"
        );
      });

      it("...unpause the Tranche contract", async () => {
        await tranche.unpauseTranche();
        expect(await tranche.paused()).to.be.false;
      });

      it("...reentrancy should fail", async () => {
        // todo: write this test later
      });

      it("...the buyer account doesn't exist for the msg.sender", async () => {
        expect(
          await tranche.ownerAddressToBuyerAccountId(deployerAddress)
        ).to.eq(0);
      });

      it("...fail if USDC is not approved", async () => {
        _protectionAmount = BigNumber.from(10).mul(USDC_DECIMALS);
        await expect(
          tranche.buyProtection(0, 0, _protectionAmount)
        ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
      });

      it("...approve 100 USDC to be transferred by the Tranche contract", async () => {
        expect(
          await USDC.approve(
            tranche.address,
            BigNumber.from(100).mul(USDC_DECIMALS)
          )
        )
          .to.emit(USDC, "Approval")
          .withArgs(
            deployerAddress,
            tranche.address,
            BigNumber.from(100).mul(USDC_DECIMALS)
          );

        const _allowanceAmount: number = await USDC.allowance(
          deployerAddress,
          tranche.address
        );
        expect(_allowanceAmount.toString()).to.eq(
          BigNumber.from(100).mul(USDC_DECIMALS).toString()
        );
      });

      it("...create a new buyer account and buy protection", async () => {
        const _initialBuyerAccountId: BigNumber = BigNumber.from(1);
        const _lendingPoolId: BigNumber = BigNumber.from(0);
        let _expirationTime: BigNumber = getUnixTimestampOfSomeMonthAhead(3);
        _protectionAmount = BigNumber.from(10).mul(USDC_DECIMALS);

        const _premiumAmount: BigNumber = await premiumPricing.calculatePremium(
          _expirationTime,
          _protectionAmount
        );

        const _initialPremiumAmountOfAccount: BigNumber = BigNumber.from(0);
        const _premiumTotalOfLendingPoolIdBefore: BigNumber =
          await tranche.lendingPoolIdToPremiumTotal(_lendingPoolId);
        const _premiumTotalBefore: BigNumber = await tranche.totalPremium();

        expect(
          await tranche.buyProtection(
            _lendingPoolId,
            _expirationTime,
            _protectionAmount
          )
        )
          .to.emit(tranche, "BuyerAccountCreated")
          .withArgs(deployerAddress, _initialBuyerAccountId)
          .to.emit(tranche, "CoverageBought")
          .withArgs(deployerAddress, _lendingPoolId, _premiumAmount);

        const _premiumAmountOfAccountAfter: BigNumber =
          await tranche.buyerAccounts(_initialBuyerAccountId, _lendingPoolId);
        const _premiumTotalOfLendingPoolIdAfter: BigNumber =
          await tranche.lendingPoolIdToPremiumTotal(_lendingPoolId);
        const _premiumTotalAfter: BigNumber = await tranche.totalPremium();

        expect(_initialPremiumAmountOfAccount.add(_premiumAmount)).to.eq(
          _premiumAmountOfAccountAfter
        );
        expect(_premiumTotalBefore.add(_premiumAmount)).to.eq(
          _premiumTotalAfter
        );
        expect(_premiumTotalOfLendingPoolIdBefore.add(_premiumAmount)).to.eq(
          _premiumTotalOfLendingPoolIdAfter
        );
      });

      it("...the buyer account for the msg.sender exists already", async () => {
        const _noBuyerAccountExist: boolean =
          (await tranche
            .ownerAddressToBuyerAccountId(deployerAddress)
            .toString()) === "0";
        expect(_noBuyerAccountExist).to.eq(false);
      });
    });

    describe("...sellProtection", async () => {
      const _underlyingAmount: BigNumber =
        BigNumber.from(10).mul(USDC_DECIMALS);
      const _exceededAmount: BigNumber =
        BigNumber.from(100000000).mul(USDC_DECIMALS);
      const _expirationTime: BigNumber = getUnixTimestampOfSomeMonthAhead(4);
      const _shortExpirationTime: BigNumber =
        getUnixTimestampOfSomeMonthAhead(2);
      const _zeroAddress: string = "0x0000000000000000000000000000000000000000";

      it("...approve 0 USDC to be transferred by the Tranche contract", async () => {
        expect(
          await USDC.approve(
            tranche.address,
            BigNumber.from(0).mul(USDC_DECIMALS)
          )
        )
          .to.emit(USDC, "Approval")
          .withArgs(
            deployerAddress,
            tranche.address,
            BigNumber.from(0).mul(USDC_DECIMALS)
          );

        const _allowanceAmount: number = await USDC.allowance(
          deployerAddress,
          tranche.address
        );
        expect(_allowanceAmount.toString()).to.eq(
          BigNumber.from(0).mul(USDC_DECIMALS).toString()
        );
      });

      it("...fail if USDC is not approved", async () => {
        await expect(
          tranche.sellProtection(
            _underlyingAmount,
            sellerAddress,
            _expirationTime
          )
        ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
      });

      it("...approve 100000000 USDC to be transferred by the Tranche contract", async () => {
        expect(
          await USDC.approve(
            tranche.address,
            BigNumber.from(100000000).mul(USDC_DECIMALS)
          )
        )
          .to.emit(USDC, "Approval")
          .withArgs(
            deployerAddress,
            tranche.address,
            BigNumber.from(100000000).mul(USDC_DECIMALS)
          );

        const _allowanceAmount: number = await USDC.allowance(
          deployerAddress,
          tranche.address
        );
        expect(_allowanceAmount.toString()).to.eq(
          BigNumber.from(100000000).mul(USDC_DECIMALS).toString()
        );
      });

      it("...fail if USDC balance is insufficient", async () => {
        await expect(
          tranche.sellProtection(
            _exceededAmount,
            sellerAddress,
            _expirationTime
          )
        ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      });

      it("...fail if an SToken receiver is a zero address", async () => {
        await expect(
          tranche.sellProtection(
            _underlyingAmount,
            _zeroAddress,
            _expirationTime
          )
        ).to.be.revertedWith("ERC20: mint to the zero address");
      });

      it("...pause the Tranche contract", async () => {
        await tranche.pauseTranche();
        expect(await tranche.paused()).to.be.true;
      });

      it("...fails if the Tranche contract is paused", async () => {
        await expect(
          tranche.sellProtection(
            _underlyingAmount,
            sellerAddress,
            _expirationTime
          )
        )
          .to.emit(tranche, "Paused")
          .withArgs(deployerAddress)
          .to.be.revertedWith("Pausable: paused");
      });

      it("...unpause the Tranche contract", async () => {
        await tranche.unpauseTranche();
        expect(await tranche.paused()).to.be.false;
      });

      it("...reentrancy should fail", async () => {
        // todo: write this test later
      });

      it("...fail if _expirationTime is not more than the minimal locking period(three months)", async () => {
        let _shortExpirationTimeString = await _shortExpirationTime;
        await expect(
          tranche.sellProtection(
            _underlyingAmount,
            sellerAddress,
            _shortExpirationTime
          )
        ).to.be.revertedWith(
          "ExpirationTimeTooShort(" +
            _shortExpirationTimeString.toString() +
            ")"
        );
      });

      it("...interest accrued", async () => {
        // todo: test accrueInterest
        // expect(
        //   await tranche.sellProtection(
        //     _underlyingAmount,
        //     sellerAddress,
        //     _expirationTime
        //   )
        // )
        //   .to.emit(tranche, "InterestAccrued")
        //   .withArgs(sellerAddress, _underlyingAmount);
      });

      // we don't have any capital from protection sellers yet. We have only 10 USDC from the protection buyer.
      it("...should return 10 total underlying amount", async () => {
        const _totalUnderlying: BigNumber = await USDC.balanceOf(
          tranche.address
        );
        expect(_totalUnderlying).to.eq(BigNumber.from(10).mul(USDC_DECIMALS));
      });

      it("...protection is sold for the 1st time", async () => {
        const _shares: BigNumber = await tranche.convertToSToken(
          _underlyingAmount
        );
        expect(_shares).to.eq(_underlyingAmount);
        expect(
          await tranche.sellProtection(
            _underlyingAmount,
            sellerAddress,
            _expirationTime
          )
        )
          .to.emit(tranche, "Transfer")
          .withArgs(sellerAddress, tranche.address, _underlyingAmount)
          .to.emit(tranche, "Minted")
          .withArgs(sellerAddress, _underlyingAmount)
          .to.emit(tranche, "ProtectionSold")
          .withArgs(sellerAddress, _underlyingAmount);
        expect(await tranche.totalCollateral()).to.eq(_underlyingAmount);
      });

      it("...should return 20 total underlying amount", async () => {
        const _totalUnderlying: BigNumber = await USDC.balanceOf(
          tranche.address
        );
        expect(_totalUnderlying).to.eq(BigNumber.from(20).mul(USDC_DECIMALS));
      });

      it("...protection is sold for the 2nd time", async () => {
        const _shares: BigNumber = await tranche.convertToSToken(
          _underlyingAmount
        );
        expect(_shares).to.not.eq(_underlyingAmount);
        expect(
          await tranche.sellProtection(
            _underlyingAmount,
            sellerAddress,
            _expirationTime
          )
        )
          .to.emit(tranche, "Transfer")
          .withArgs(sellerAddress, tranche.address, _underlyingAmount)
          .to.emit(tranche, "Minted")
          .withArgs(sellerAddress, _underlyingAmount)
          .to.emit(tranche, "ProtectionSold")
          .withArgs(sellerAddress, _underlyingAmount);
        expect(await tranche.totalCollateral()).to.eq(
          _underlyingAmount.add(_underlyingAmount)
        );
        // shares == _underlyingAmount in the 1st protection purchase
        expect(_shares.add(_underlyingAmount)).to.eq(
          await tranche.balanceOf(sellerAddress)
        );
      });

      it("...should return 30 total underlying amount", async () => {
        const _totalUnderlying: BigNumber = await USDC.balanceOf(
          tranche.address
        );
        expect(_totalUnderlying).to.eq(BigNumber.from(30).mul(USDC_DECIMALS));
      });
    });

    describe("pauseTranche", () => {
      it("...should allow the owner to pause contract", async () => {
        await expect(tranche.connect(owner).pauseTranche()).to.be.revertedWith(
          "Ownable: caller is not the owner"
        );
        expect(await tranche.connect(deployer).pauseTranche()).to.emit(
          tranche,
          "Paused"
        );
        const _paused: boolean = await tranche.paused();
        expect(_paused).to.eq(true);
      });
    });

    describe("unpauseTranche", () => {
      it("...should allow the owner to unpause contract", async () => {
        await expect(
          tranche.connect(owner).unpauseTranche()
        ).to.be.revertedWith("Ownable: caller is not the owner");
        expect(await tranche.connect(deployer).unpauseTranche()).to.emit(
          tranche,
          "Unpaused"
        );
        const _paused: boolean = await tranche.paused();
        expect(_paused).to.eq(false);
      });
    });
  });
};

export { tranche };
