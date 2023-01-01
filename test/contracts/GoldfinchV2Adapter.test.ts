import { expect } from "chai";
import { parseEther } from "ethers/lib/utils";

import { GoldfinchV2Adapter } from "../../typechain-types/contracts/adapters/GoldfinchV2Adapter";
import { ProtectionPurchaseParamsStruct } from "../../typechain-types/contracts/interfaces/IReferenceLendingPools";
import { parseUSDC } from "../utils/usdc";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";
import { ethers, network } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
  getDaysInSeconds,
  getLatestBlockTimestamp,
  moveForwardTime,
  moveForwardTimeByDays,
  setNextBlockTimestamp
} from "../utils/time";
import { toBytes32, setStorageAt, getStorageAt } from "../utils/storage";

const GOLDFINCH_ALMAVEST_BASKET_6_ADDRESS =
  "0x418749e294cabce5a714efccc22a8aade6f9db57";
const BUYER1 = "0x0196ad265c56f2b18b708c75ce9358a0b6df64cf";
const BUYER2 = "0x1b027485ee2ba9b2e9b43689435188b1a1556a1c";
const BUYER3 = "0x10a590f528eff3d5de18c90da6e03a4acdde3a7d";

const testGoldfinchV2Adapter: Function = (
  goldfinchV2Adapter: GoldfinchV2Adapter
) => {
  describe("GoldfinchV2Adapter", () => {
    let _snapshotId: string;

    before(async () => {
      _snapshotId = await network.provider.send("evm_snapshot", []);
    });

    after(async () => {
      // Some specs move time forward, revert the state to the snapshot
      expect(await network.provider.send("evm_revert", [_snapshotId])).to.eq(
        true
      );
    });

    describe("constructor", () => {
      it("...should set the correct goldfinch config", async () => {
        expect(await goldfinchV2Adapter.goldfinchConfig()).to.equal(
          await goldfinchV2Adapter.GOLDFINCH_CONFIG_ADDRESS()
        );
      });
    });

    describe("isLendingPoolLate", () => {
      it("...should return false for a pool current payment", async () => {
        expect(
          await goldfinchV2Adapter.isLendingPoolLate(
            "0x759f097f3153f5d62ff1c2d82ba78b6350f223e3"
          )
        ).to.be.false;
      });

      it("...should return true for a pool with late payment", async () => {
        // see: https://app.goldfinch.finance/pools/0x00c27fc71b159a346e179b4a1608a0865e8a7470
        expect(
          await goldfinchV2Adapter.isLendingPoolLate(
            "0x00c27fc71b159a346e179b4a1608a0865e8a7470"
          )
        ).to.be.true;
      });
    });

    describe("isLendingPoolExpired", () => {
      it("...should return true for a pool with balance = 0", async () => {
        // see: https://app.goldfinch.finance/pools/0xf74ea34ac88862b7ff419e60e476be2651433e68
        expect(
          await goldfinchV2Adapter.isLendingPoolExpired(
            "0xf74ea34ac88862b7ff419e60e476be2651433e68"
          )
        ).to.be.true;
      });

      it("...should return true for a pool with term ended", async () => {
        /// slot 460 represents the termEnd
        // pool: 0xc9bdd0d3b80cc6efe79a82d850f44ec9b55387ae;
        // creditline: https://etherscan.io/address/0x7666dE84357dB649D973232834d6456AF3fA61BC#readContract
        const termEndSlot = 460;
        const lendingPool = "0xc9bdd0d3b80cc6efe79a82d850f44ec9b55387ae";
        const tranchedPool = (await ethers.getContractAt(
          "ITranchedPool",
          lendingPool
        )) as ITranchedPool;
        const creditLine = await tranchedPool.creditLine();

        expect(creditLine).to.equal(
          "0x7666dE84357dB649D973232834d6456AF3fA61BC"
        );
        expect(await getStorageAt(creditLine, termEndSlot)).to.eq(
          "0x00000000000000000000000000000000000000000000000000000000673127ab"
        );

        const termEndInPast = (await getLatestBlockTimestamp()) - 2;
        await setStorageAt(
          creditLine,
          termEndSlot,
          toBytes32(BigNumber.from(termEndInPast)).toString()
        );
        expect(await goldfinchV2Adapter.isLendingPoolExpired(lendingPool)).to.be
          .true;
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
      let _purchaseParams: ProtectionPurchaseParamsStruct;
      before("set up", async () => {
        _purchaseParams = {
          lendingPoolAddress: GOLDFINCH_ALMAVEST_BASKET_6_ADDRESS,
          nftLpTokenId: 452,
          protectionAmount: parseUSDC("100"),
          protectionDurationInSeconds: getDaysInSeconds(30)
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

    describe("calculateRemainingPrincipal", () => {
      it("...should return the correct remaining principal", async () => {
        // token info: pool,                           tranche, principal,    principalRedeemed, interestRedeemed
        // 0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf, 2,       420000000000, 223154992,         35191845008
        expect(
          await goldfinchV2Adapter.calculateRemainingPrincipal(
            "0x008c84421da5527f462886cec43d2717b686a7e4",
            590
          )
        ).to.eq(parseUSDC("419776.845008"));
      });

      it("...should return the 0 remaining principal for non-owner", async () => {
        // lender doesn't own the NFT
        expect(
          await goldfinchV2Adapter.calculateRemainingPrincipal(
            "0x008c84421da5527f462886cec43d2717b686a7e4",
            591
          )
        ).to.eq(0);
      });
    });

    describe("isLendingPoolLateWithinGracePeriod", () => {
      it("...should return false when payment is not late", async () => {
        // Payment is not late, so should return false
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            1
          )
        ).to.eq(false);

        // Move time forward by 30 days from last payment timestamp
        const lastPaymentTimestamp =
          await goldfinchV2Adapter.getLatestPaymentTimestamp(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
          );
        await setNextBlockTimestamp(
          lastPaymentTimestamp.add(getDaysInSeconds(30))
        );

        // This means, payment is still not late and should return false
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            1
          )
        ).to.eq(false);
      });

      it("...should return true when payment is late but within grace period", async () => {
        // Move time forward by 1 second
        await moveForwardTime(BigNumber.from(1));

        // Payment is late, so should return true
        expect(
          await goldfinchV2Adapter.isLendingPoolLate(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
          )
        ).to.eq(true);

        // Lending pool is late but within grace period, so should return true
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            1
          )
        ).to.eq(true);
      });

      it("...should return false when payment is late and after grace period", async () => {
        // Move time forward by a day
        await moveForwardTime(getDaysInSeconds(1));

        // Payment is late, so should return true
        expect(
          await goldfinchV2Adapter.isLendingPoolLate(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
          )
        ).to.eq(true);

        // Lending pool is late and after grace period, so should return false
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            1
          )
        ).to.eq(false);
      });

      it("...should return false when payment is late and after grace period", async () => {
        // Move time forward by a day
        await moveForwardTime(getDaysInSeconds(1));

        // Payment is late, so should return true
        expect(
          await goldfinchV2Adapter.isLendingPoolLate(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
          )
        ).to.eq(true);

        // Lending pool is late and within longer grace period, so should return true
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            1
          )
        ).to.eq(false);
      });

      it("...should return true when payment is late and within longer grace period", async () => {
        // Lending pool is late and within longer grace period, so should return true
        // Total time elapsed since last payment = 30 days + 2 days + 1 second
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            3
          )
        ).to.eq(true);
      });

      it("...should return false when payment is late and after longer grace period", async () => {
        // Move time forward by another 2 days
        await moveForwardTime(getDaysInSeconds(2));

        // Total time elapsed since last payment = 30 days + 4 days + 1 second
        // Lending pool is late and after grace period of 4 days, so should return false
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            4
          )
        ).to.eq(false);

        // Lending pool is late but longer grace period of 5 days, so should return true
        expect(
          await goldfinchV2Adapter.isLendingPoolLateWithinGracePeriod(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf",
            5
          )
        ).to.eq(true);
      });
    });

    describe("getPaymentPeriodInDays", () => {
      it("...should return the correct payment period", async () => {
        expect(
          await goldfinchV2Adapter.getPaymentPeriodInDays(
            "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
          )
        ).to.eq(BigNumber.from(30));
      });
    });
  });
};

export { testGoldfinchV2Adapter };
