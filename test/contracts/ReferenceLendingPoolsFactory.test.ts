import { expect } from "chai";
import { Signer } from "ethers/lib/ethers";
import { ZERO_ADDRESS } from "../../test/utils/constants";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ReferenceLendingPoolsFactory } from "../../typechain-types/contracts/core/ReferenceLendingPoolsFactory";
import { getDaysInSeconds, getLatestBlockTimestamp } from "../utils/time";

const LENDING_POOL_1 = "0x759f097f3153f5d62ff1c2d82ba78b6350f223e3";

const testReferenceLendingPoolsFactory: Function = (
  deployer: Signer,
  account1: Signer,
  referenceLendingPoolsImplementation: ReferenceLendingPools,
  referenceLendingPoolsFactory: ReferenceLendingPoolsFactory,
  getReferenceLendingPoolsInstanceFromTx: Function
) => {
  describe("ReferenceLendingPoolsFactory", () => {
    describe("constructor", () => {
      it("...should set the implementation address", async () => {
        expect(
          await referenceLendingPoolsFactory.referenceLendingPoolsImplementation()
        ).to.equal(referenceLendingPoolsImplementation.address);
      });
    });

    describe("createReferenceLendingPools", () => {
      it("...should revert when not called by owner", async () => {
        await expect(
          referenceLendingPoolsFactory
            .connect(account1)
            .createReferenceLendingPools([ZERO_ADDRESS], [0], [0])
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...should revert when new pool is created with zero address by owner", async () => {
        await expect(
          referenceLendingPoolsFactory
            .connect(deployer)
            .createReferenceLendingPools([ZERO_ADDRESS], [0], [0])
        ).to.be.revertedWith("ReferenceLendingPoolIsZeroAddress");
      });

      it("...should revert when array lengths are not equal", async () => {
        await expect(
          referenceLendingPoolsFactory.createReferenceLendingPools(
            [ZERO_ADDRESS],
            [],
            []
          )
        ).to.be.revertedWith("Array inputs length must match");

        await expect(
          referenceLendingPoolsFactory.createReferenceLendingPools([], [0], [])
        ).to.be.revertedWith("Array inputs length must match");

        await expect(
          referenceLendingPoolsFactory.createReferenceLendingPools(
            [ZERO_ADDRESS],
            [0],
            [10, 11]
          )
        ).to.be.revertedWith("Array inputs length must match");
      });

      it("...should create an instance of ReferenceLendingPools successfully", async () => {
        const _purchaseLimitInDays = 30;
        const tx = await referenceLendingPoolsFactory
          .connect(deployer)
          .createReferenceLendingPools(
            [LENDING_POOL_1],
            [0],
            [_purchaseLimitInDays]
          );
        const referenceLendingPoolsInstance =
          await getReferenceLendingPoolsInstanceFromTx(tx);

        const lendingPoolInfo =
          await referenceLendingPoolsInstance.referenceLendingPools(
            LENDING_POOL_1
          );

        const _expectedLatestTimestamp = await getLatestBlockTimestamp();
        const _expectedPurchaseLimitTimestamp =
          _expectedLatestTimestamp +
          getDaysInSeconds(_purchaseLimitInDays).toNumber();

        expect(lendingPoolInfo.protocol).to.be.eq(0); // GoldfinchV2
        expect(lendingPoolInfo.addedTimestamp).to.be.eq(
          _expectedLatestTimestamp
        );
        expect(lendingPoolInfo.protectionPurchaseLimitTimestamp).to.be.eq(
          _expectedPurchaseLimitTimestamp
        );

        expect(await referenceLendingPoolsInstance.owner()).to.be.eq(
          await deployer.getAddress()
        );
      });
    });
  });
};

export { testReferenceLendingPoolsFactory };
