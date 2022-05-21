import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { USDC_ADDRESS, USDC_DECIMALS, USDC_ABI } from "../utils/constants";
import { PremiumPricing } from "../../typechain-types/contracts/core/PremiumPricing";
import { Tranche } from "../../typechain-types/contracts/core/Tranche";

const tranche: Function = (
  deployer: Signer,
  account1: Signer,
  premiumPricing: PremiumPricing,
  tranche: Tranche
) => {
  describe("Tranche", () => {
    let deployerAddress: string;
    let account1Address: string;
    let USDC: Contract;

    before("get addresses", async () => {
      deployerAddress = await deployer.getAddress();
      account1Address = await account1.getAddress();
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
