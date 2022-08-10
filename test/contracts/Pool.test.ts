import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import {
  CIRCLE_ACCOUNT_ADDRESS,
  USDC_ADDRESS,
  USDC_DECIMALS,
  USDC_ABI
} from "../utils/constants";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { ReferenceLoans } from "../../typechain-types/contracts/core/pool/ReferenceLoans";
import { getUnixTimestampOfSomeMonthAhead } from "../utils/time";
import { ethers } from "hardhat";
import { Tranche } from "../../typechain-types/contracts/core/tranche/Tranche";

const testPool: Function = (
  account1: Signer,
  pool: Pool,
  referenceLoans: ReferenceLoans
) => {
  describe("Pool", () => {
    const _newFloor: BigNumber = BigNumber.from(100);
    const _newCeiling: BigNumber = BigNumber.from(500);
    let poolInfo: any;
    let USDC: Contract;

    before("get the pool info", async () => {
      poolInfo = await pool.poolInfo();

      USDC = await new Contract(USDC_ADDRESS, USDC_ABI, account1);

      // Impersonate CIRCLE account and transfer some USDC to accoun1 to test with
      const circleAccount = await ethers.getImpersonatedSigner(
        CIRCLE_ACCOUNT_ADDRESS
      );
      USDC.connect(circleAccount).transfer(
        await account1.getAddress(),
        BigNumber.from(100000).mul(USDC_DECIMALS)
      );
    });

    describe("constructor", () => {
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
        expect(poolInfo.params.underlyingToken.toString()).to.eq(USDC_ADDRESS);
      });
      it("...set the reference loans", async () => {
        expect(poolInfo.params.referenceLoans.toString()).to.eq(
          referenceLoans.address
        );
      });
      it("...creates a tranche", async () => {
        expect(await pool.tranche()).not.to.be.undefined;
        expect(await pool.tranche()).not.to.be.null;
      });
    });

    describe("updateFloor", () => {
      it("...only the owner should be able to call the updateFloor function", async () => {
        await expect(
          pool.connect(account1).updateFloor(_newFloor)
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });

    describe("updateCeiling", () => {
      it("...only the owner should be able to call the updateCeiling function", async () => {
        await expect(
          pool.connect(account1).updateCeiling(_newCeiling)
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });

    describe("calculateLeverageRatio", () => {
      it("...should return 0 when tranche has no protection sold", async () => {
        expect(await pool.calculateLeverageRatio()).to.equal(0);
      });

      // TODO: setup PoolCycleManager to allow for deposit and use new deposit function
      xit("...should return correct ratio when tranche has atleast 1 protection bought & sold", async () => {
        const tranche: Tranche = (await ethers.getContractAt(
          "Tranche",
          await pool.tranche()
        )) as Tranche;
        let expirationTime: BigNumber = getUnixTimestampOfSomeMonthAhead(4);
        let protectionAmount = BigNumber.from(100000).mul(USDC_DECIMALS); // 100K USDC

        await USDC.approve(
          tranche.address,
          BigNumber.from(20000).mul(USDC_DECIMALS)
        ); // 20K USDC
        await tranche
          .connect(account1)
          .buyProtection(0, expirationTime, protectionAmount);

        // await tranche.connect(account1).sellProtection(BigNumber.from(10000).mul(USDC_DECIMALS), await account1.getAddress(), expirationTime);

        // Leverage ratio should be liitle bit higher than 0.1 (scaled by 10^18) because of accrued premium
        expect(await pool.calculateLeverageRatio()).to.be.gt(parseEther("0.1"));
        expect(await pool.calculateLeverageRatio()).to.be.lt(
          parseEther("0.101")
        );
      });
    });
  });
};

export { testPool };
