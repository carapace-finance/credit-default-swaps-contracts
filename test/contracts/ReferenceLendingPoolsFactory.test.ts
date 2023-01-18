import { expect } from "chai";
import { Signer } from "ethers/lib/ethers";
import { ZERO_ADDRESS } from "../../test/utils/constants";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ReferenceLendingPoolsFactory } from "../../typechain-types/contracts/core/ReferenceLendingPoolsFactory";
import { LendingProtocolAdapterFactory } from "../../typechain-types/contracts/core/LendingProtocolAdapterFactory";
import { getDaysInSeconds, getLatestBlockTimestamp } from "../utils/time";

const LENDING_POOL_1 = "0x759f097f3153f5d62ff1c2d82ba78b6350f223e3";

const testReferenceLendingPoolsFactory: Function = (
  deployer: Signer,
  account1: Signer,
  referenceLendingPoolsImplementation: ReferenceLendingPools,
  referenceLendingPoolsFactory: ReferenceLendingPoolsFactory,
  lendingProtocolAdapterFactory: LendingProtocolAdapterFactory,
  getLatestReferenceLendingPoolsInstance: Function
) => {
  describe("ReferenceLendingPoolsFactory", () => {
    describe("constructor", () => {
      it("...should be valid instance", async () => {
        expect(referenceLendingPoolsFactory).to.not.equal(undefined);
      });
    });

    describe("createReferenceLendingPools", () => {
      it("...should revert when not called by owner", async () => {
        await expect(
          referenceLendingPoolsFactory
            .connect(account1)
            .createReferenceLendingPools(
              referenceLendingPoolsImplementation.address,
              [ZERO_ADDRESS],
              [0],
              [0],
              ZERO_ADDRESS
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...should revert when new pool is created with zero address by owner", async () => {
        await expect(
          referenceLendingPoolsFactory
            .connect(deployer)
            .createReferenceLendingPools(
              ZERO_ADDRESS,
              [ZERO_ADDRESS],
              [0],
              [0],
              ZERO_ADDRESS
            )
        ).to.be.revertedWith("ERC1967: new implementation is not a contract");
      });

      it("...should revert when lending pools and protocols array lengths are not equal", async () => {
        await expect(
          referenceLendingPoolsFactory.createReferenceLendingPools(
            referenceLendingPoolsImplementation.address,
            [ZERO_ADDRESS],
            [],
            [],
            ZERO_ADDRESS
          )
        ).to.be.revertedWith;
      });

      it("...should revert when lending protocols and purchase limit days array lengths are not equal", async () => {
        await expect(
          referenceLendingPoolsFactory.createReferenceLendingPools(
            referenceLendingPoolsImplementation.address,
            [ZERO_ADDRESS],
            [0],
            [10, 11],
            ZERO_ADDRESS
          )
        ).to.be.revertedWith;
      });

      it("...should create an instance of ReferenceLendingPools successfully", async () => {
        const _purchaseLimitInDays = 30;
        const tx = await referenceLendingPoolsFactory
          .connect(deployer)
          .createReferenceLendingPools(
            referenceLendingPoolsImplementation.address,
            [LENDING_POOL_1],
            [0],
            [_purchaseLimitInDays],
            lendingProtocolAdapterFactory.address
          );
        const referenceLendingPoolsInstance =
          await getLatestReferenceLendingPoolsInstance(
            referenceLendingPoolsFactory
          );

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
