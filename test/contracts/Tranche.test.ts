import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { USDC_ADDRESS, USDC_DECIMALS, USDC_ABI } from "../utils/constants";
import { PremiumPricing } from "../../typechain-types/contracts/core/PremiumPricing";
import { Tranche } from "../../typechain-types/contracts/core/Tranche";
import { getUnixTimestampOfSomeMonthAhead } from "../utils/time";

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
    let USDC: Contract;

    before("get addresses", async () => {
      deployerAddress = await deployer.getAddress();
      ownerAddress = await owner.getAddress();
    });

    before("instantiate USDC token contract", async () => {
      USDC = await new Contract(USDC_ADDRESS, USDC_ABI, deployer);
    });

    describe("constructor", () => {
      it("...set the LP token name", async () => {
        const _name: string = await tranche.name();
        // need to come up with a better name
        expect(_name).to.eq("lpToken");
      });
      it("...set the LP token symbol", async () => {
        const _symbol: string = await tranche.symbol();
        // need to come up with a better symbol
        expect(_symbol).to.eq("LPT");
      });
      it("...set the USDC as the payment token", async () => {
        const _paymentTokenAddress: string = await tranche.paymentToken();
        expect(_paymentTokenAddress).to.eq(USDC_ADDRESS);
      });
      it("...set the reference lending pool contract address", async () => {
        const _referenceLendingPoolsAddress: string =
          await tranche.referenceLendingPools();
        // the _referenceLendingPoolsAddress should not be USDC_ADDRESS
        expect(_referenceLendingPoolsAddress).to.eq(USDC_ADDRESS);
      });
      it("...set the premium pricing contract address", async () => {
        const _premiumPricingAddress: string = await tranche.premiumPricing();
        // the _premiumPricingAddress should not be USDC_ADDRESS
        expect(_premiumPricingAddress).to.eq(USDC_ADDRESS);
      });
    });

    describe("buyCoverage", () => {
      it("...should expire the referenceLoans", async () => {
        // write this test once you finish writing the ReferenceLendingPools contract
        //   await referenceLoans.setIsExpired(true);
        //   const _checkIsExpired: boolean =
        //     await referenceLoans.checkIsExpired();
        //   expect(_checkIsExpired.toString()).to.eq("true");
      });

      it("...fails if the lending pool has expired already", async () => {
        // write this test once you finish writing the ReferenceLendingPools contract
        // expect(await tranche.buyCoverage(0,0,0)).to.be.revertedWith("Lending pool has expired");
      });

      it("...should roll back the expiration the referenceLoans for testing", async () => {
        // write this test once you finish writing the ReferenceLendingPools contract
        //   await referenceLoans.setIsExpired(true);
        //   const _checkIsExpired: boolean =
        //     await referenceLoans.checkIsExpired();
        //   expect(_checkIsExpired.toString()).to.eq("true");
      });

      it("...fails if the lending pool has defaulted", async () => {
        // write this test once you finish writing the ReferenceLendingPools contract
        // even if a pool defaults, there may be more default from other loans in the pool. whenNotDefault should be valid only when all the loans in the lending pool default?
      });

      it("...fails if the Tranche contract is paused", async () => {
        await tranche.pauseTranche();
        await expect(tranche.buyCoverage(0, 0, 0))
          .to.emit(tranche, "Paused")
          .withArgs(deployerAddress)
          .to.be.revertedWith("Pausable: paused");
        expect(await tranche.paused()).to.be.true;
      });

      it("...unpause the Tranche contract", async () => {
        await tranche.unpauseTranche();
        expect(await tranche.paused()).to.be.false;
      });

      it("...reentrancy should fail", async () => {
        // write this test later
      });

      it("...the buyer account doesn't exist for the msg.sender", async () => {
        const _noBuyerAccountExist: boolean =
          (await tranche
            .ownerAddressToBuyerAccountId(deployerAddress)
            .toString()) === "0";
        expect(_noBuyerAccountExist).to.eq(true);
      });

      it("...fail if USDC is not approved", async () => {
        expect(await tranche.buyCoverage(0, 0, 0)).to.be.revertedWith(
          "ERC20: insufficient allowance"
        );
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
        await expect(_allowanceAmount.toString()).to.eq(
          BigNumber.from(100).mul(USDC_DECIMALS).toString()
        );
      });

      it("...create a new buyer account and buy coverage", async () => {
        const _buyerAccountId: BigNumber =
          await tranche.ownerAddressToBuyerAccountId(deployerAddress);
        const _lendingPoolId: string = "0";
        let _expirationTime: BigNumber = getUnixTimestampOfSomeMonthAhead(3);
        let _coverageAmount: BigNumber = BigNumber.from(10).mul(
          BigNumber.from(10).pow(USDC_DECIMALS)
        );

        const _premiumAmount: BigNumber = await premiumPricing.calculatePremium(
          _expirationTime,
          _coverageAmount
        );

        const _accountId: BigNumber =
          await tranche.ownerAddressToBuyerAccountId(deployerAddress);
        const _premiumAmountOfAccountBefore: BigNumber =
          await tranche.buyerAccounts(_accountId, _lendingPoolId);
        const _premiumTotalOfLendingPoolIdBefore: BigNumber =
          await tranche.lendingPoolIdToPremiumTotal(_lendingPoolId);
        const _premiumTotalBefore: BigNumber = await tranche.premiumTotal();

        await expect(
          tranche.buyCoverage(_lendingPoolId, _expirationTime, _coverageAmount)
        )
          .to.emit(tranche, "BuyerAccountCreated")
          .withArgs(deployerAddress, _buyerAccountId)
          .to.emit(tranche, "CoverageBought")
          .withArgs(deployerAddress, _lendingPoolId, _premiumAmount);

        const _premiumAmountOfAccountAfter: BigNumber =
          await tranche.buyerAccounts(_accountId, _lendingPoolId);
        const _premiumTotalOfLendingPoolIdAfter: BigNumber =
          await tranche.lendingPoolIdToPremiumTotal(_lendingPoolId);
        const _premiumTotalAfter: BigNumber = await tranche.premiumTotal();

        expect(_premiumAmountOfAccountBefore.add(_premiumAmount)).to.eq(
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

    describe("pauseTranche", () => {
      it("...should allow owner to pause contract", async () => {
        await expect(
          tranche.connect(account1).pauseTranche()
        ).to.be.revertedWith("Ownable: caller is not the owner");
        await expect(tranche.connect(deployer).pauseTranche()).to.emit(
          tranche,
          "Paused"
        );
        const _paused: boolean = await tranche.paused();
        expect(_paused).to.eq(true);
      });
    });

    describe("unpauseTranche", () => {
      it("...should allow owner to unpause contract", async () => {
        await expect(
          tranche.connect(account1).unpauseTranche()
        ).to.be.revertedWith("Ownable: caller is not the owner");
        await expect(tranche.connect(deployer).unpauseTranche()).to.emit(
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
