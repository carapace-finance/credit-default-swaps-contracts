import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { Signer } from "ethers";
import { USDC_ADDRESS } from "../utils/constants";
import { Pool } from "../../typechain-types/contracts/core/pool/Pool";
import { ReferenceLoans } from "../../typechain-types/contracts/core/pool/ReferenceLoans";

const testPool: Function = (
  account1: Signer,
  pool: Pool,
  referenceLoans: ReferenceLoans
) => {
  describe("Pool", () => {
    const _newFloor: BigNumber = BigNumber.from(100);
    const _newCeiling: BigNumber = BigNumber.from(500);
    let poolInfo: any;

    before("get the pool info", async () => {
      poolInfo = await pool.poolInfo();
    });

    describe("constructor", () => {
      it("...set the pool id", async () => {
        expect(poolInfo.poolId.toString()).to.eq("1");
      });
      it("...set the floor", async () => {
        expect(poolInfo.params.leverageRatioFloor.toString()).to.eq("100");
      });
      it("...set the ceiling", async () => {
        expect(poolInfo.params.leverageRatioCeiling.toString()).to.eq("500");
      });
      it("...set the underlying token", async () => {
        expect(poolInfo.params.underlyingToken.toString()).to.eq(USDC_ADDRESS);
      });
      it("...set the reference loans", async () => {
        expect(poolInfo.params.referenceLoans.toString()).to.eq(
          referenceLoans.address
        );
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
  });
};

export { testPool };
