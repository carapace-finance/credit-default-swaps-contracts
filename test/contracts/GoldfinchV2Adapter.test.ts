import { expect } from "chai";
import { parseEther } from "ethers/lib/utils";

import { GoldfinchV2Adapter } from "../../typechain-types/contracts/adapters/GoldfinchV2Adapter";
import { IReferenceLendingPools } from "../../typechain-types/contracts/interfaces/IReferenceLendingPools";
import { parseUSDC } from "../utils/usdc";
import { ISeniorPool } from "../../typechain-types/contracts/external/goldfinch/ISeniorPool";

const GOLDFINCH_ALMAVEST_BASKET_6_ADDRESS =
  "0x418749e294cabce5a714efccc22a8aade6f9db57";
const BUYER1 = "0x0196ad265c56f2b18b708c75ce9358a0b6df64cf";
const BUYER2 = "0x1b027485ee2ba9b2e9b43689435188b1a1556a1c";
const BUYER3 = "0x10a590f528eff3d5de18c90da6e03a4acdde3a7d";

const testGoldfinchV2Adapter: Function = (
  goldfinchV2Adapter: GoldfinchV2Adapter
) => {
  describe("GoldfinchV2Adapter", () => {
    describe("constructor", () => {
      it("...should set the correct goldfinch config", async () => {
        expect(await goldfinchV2Adapter.goldfinchConfig()).to.equal(
          await goldfinchV2Adapter.GOLDFINCH_CONFIG_ADDRESS()
        );

        // const seniorPool = (await ethers.getContractAt(
        //   "ISeniorPool",
        //   "0x8481a6EbAf5c7DABc3F7e09e44A89531fd31F822"
        // )) as ISeniorPool;
      });
    });

    describe("isLendingPoolDefaulted", () => {
      it("...should return false for a pool with writedown = 0", async () => {
        expect(
          await goldfinchV2Adapter.isLendingPoolDefaulted(
            GOLDFINCH_ALMAVEST_BASKET_6_ADDRESS
          )
        ).to.be.false;
      });

      // Could not find a pool with writedown > 0
      xit("...should return true for a pool with writedown > 0", async () => {
        expect(await goldfinchV2Adapter.isLendingPoolDefaulted("")).to.be.false;
      });
    });

    describe("isLendingPoolExpired", () => {
      it("...should return true for a pool with balance = 0", async () => {
        // se: https://app.goldfinch.finance/pools/0xf74ea34ac88862b7ff419e60e476be2651433e68
        expect(
          await goldfinchV2Adapter.isLendingPoolExpired(
            "0xf74ea34ac88862b7ff419e60e476be2651433e68"
          )
        ).to.be.true;
      });

      // Could not find a pool with term ended
      xit("...should return true for a pool with term ended", async () => {
        expect(await goldfinchV2Adapter.isLendingPoolExpired("")).to.be.true;
      });
    });

    describe("getLendingPoolTermEndTimestamp", () => {
      it("...should return the correct term end timestamp", async () => {
        const termEndTimestamp =
          await goldfinchV2Adapter.getLendingPoolTermEndTimestamp(
            GOLDFINCH_ALMAVEST_BASKET_6_ADDRESS
          );
        // creditLine: https://etherscan.io/address/0x0099f9b99956a495e6c59d9105193ea46abe2d56#readContract#F27
        expect(termEndTimestamp).to.eq(1740068036);
      });
    });

    describe("calculateProtectionBuyerAPR", () => {
      it("...should return the correct interest rate", async () => {
        // see USDC APY: https://app.goldfinch.finance/pools/0x418749e294cabce5a714efccc22a8aade6f9db57
        expect(
          await goldfinchV2Adapter.calculateProtectionBuyerAPR(
            GOLDFINCH_ALMAVEST_BASKET_6_ADDRESS
          )
        ).to.eq(parseEther("0.17"));

        // see USDC APY: https://app.goldfinch.finance/pools/0x00c27fc71b159a346e179b4a1608a0865e8a7470
        expect(
          await goldfinchV2Adapter.calculateProtectionBuyerAPR(
            "0x00c27fc71b159a346e179b4a1608a0865e8a7470"
          )
        ).to.eq(parseEther("0.187"));
      });
    });

    describe("isProtectionAmountValid", () => {
      let _purchaseParams: IReferenceLendingPools.ProtectionPurchaseParamsStruct;
      before("set up", async () => {
        _purchaseParams = {
          lendingPoolAddress: GOLDFINCH_ALMAVEST_BASKET_6_ADDRESS,
          nftLpTokenId: 452,
          protectionAmount: parseUSDC("100"),
          protectionExpirationTimestamp: 1740068036
        };
      });

      it("...should return true if the protection amount is valid", async () => {
        // principal amt for the buyer: 3298.142704
        expect(
          await goldfinchV2Adapter.isProtectionAmountValid(
            BUYER1,
            _purchaseParams
          )
        ).to.eq(true);
      });

      it("...should return false when the protection amount is greater than principal", async () => {
        // principal amt for the buyer: 3298.142704
        const _protectionAmount = parseUSDC("5000");
        _purchaseParams.protectionAmount = _protectionAmount;

        expect(
          await goldfinchV2Adapter.isProtectionAmountValid(
            BUYER1,
            _purchaseParams
          )
        ).to.be.false;
      });

      it("...should return false when the buyer does not own the NFT specified", async () => {
        expect(
          await goldfinchV2Adapter.isProtectionAmountValid(
            BUYER2,
            _purchaseParams
          )
        ).to.be.false;
      });

      it("...should return false when the buyer owns the NFT for different pool", async () => {
        _purchaseParams.nftLpTokenId = 142;

        expect(
          await goldfinchV2Adapter.isProtectionAmountValid(
            BUYER3,
            _purchaseParams
          )
        ).to.be.false;
      });
    });
  });
};

export { testGoldfinchV2Adapter };