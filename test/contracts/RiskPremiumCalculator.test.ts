import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { parseEther, formatEther } from "ethers/lib/utils";
import { IPool } from "../../typechain-types/contracts/core/pool/Pool";
import { parseUSDC } from "../utils/usdc";

import { RiskPremiumCalculator } from "../../typechain-types/contracts/core/RiskPremiumCalculator";
import { getUnixTimestampAheadByDays } from "../utils/time";

const testRiskPremiumCalculator: Function = (
  riskPremiumCalculator: RiskPremiumCalculator
) => {
  describe("RiskPremiumCalculator", () => {
    const _curvature: BigNumber = parseEther("0.05");
    const _leverageRatioFloor: BigNumber = parseEther("0.1");
    const _leverageRatioCeiling: BigNumber = parseEther("0.2");
    const _leverageRatioBuffer: BigNumber = parseEther("0.05");
    const _protectionAmt = parseEther("100000"); // 100k
    const _currentLeverageRatio = parseEther("0.15"); // 15%
    const _protectionBuyerApy = parseEther("0.17"); // 17%

    const poolCycleParams: IPool.PoolCycleParamsStruct = {
      openCycleDuration: BigNumber.from(10 * 86400), // 10 days
      cycleDuration: BigNumber.from(30 * 86400) // 30 days
    };
    const _poolParams: IPool.PoolParamsStruct = {
      leverageRatioFloor: _leverageRatioFloor,
      leverageRatioCeiling: _leverageRatioCeiling,
      leverageRatioBuffer: _leverageRatioBuffer,
      minRequiredCapital: parseUSDC("10000"),
      minRequiredProtection: parseUSDC("20000"),
      curvature: _curvature,
      minRiskPremiumPercent: parseEther("0.02"), // 2%
      underlyingRiskPremiumPercent: parseEther("0.1"), // 10%
      poolCycleParams: poolCycleParams
    };

    describe("calculatePremium", () => {
      it("... calculates correct premium amount for a leverage ratio 0", async () => {
        const _expirationTimestamp = await getUnixTimestampAheadByDays(180);

        const premium = await riskPremiumCalculator.calculatePremium(
          _expirationTimestamp,
          _protectionAmt,
          _protectionBuyerApy,
          0,
          _poolParams
        );
        console.log(`Premium: ${formatEther(premium)}`);

        expect(premium)
          .to.be.gt(parseEther("2837.8052"))
          .and.lt(parseEther("2837.8053"));
      });

      it("... calculates correct premium amount for a period of 180 days", async () => {
        const _expirationTimestamp = await getUnixTimestampAheadByDays(180);

        const premium = await riskPremiumCalculator.calculatePremium(
          _expirationTimestamp,
          _protectionAmt,
          _protectionBuyerApy,
          _currentLeverageRatio,
          _poolParams
        );
        console.log(`Premium: ${formatEther(premium)}`);

        expect(premium)
          .to.be.gt(parseEther("3271.8265"))
          .and.lt(parseEther("3271.8266"));
      });

      it("... calculates correct premium amount for a period of 365 days", async () => {
        const _expirationTimestamp = await getUnixTimestampAheadByDays(365);

        const premium = await riskPremiumCalculator.calculatePremium(
          _expirationTimestamp,
          _protectionAmt,
          _protectionBuyerApy,
          _currentLeverageRatio,
          _poolParams
        );
        console.log(`Premium: ${formatEther(premium)}`);

        expect(premium)
          .to.be.gt(parseEther("6572.8151"))
          .and.lt(parseEther("6572.8152"));
      });

      it("... calculates premium amount without overflow/underflow for a range of leverage ratio from 0.1 to 0.2", async () => {
        const _expirationTimestamp = await getUnixTimestampAheadByDays(365 * 2); // 2 years

        let leverageRatio = _leverageRatioFloor;
        let protectionAmount = _protectionAmt;
        let protectionBuyerApy = parseEther("0.1");
        while (leverageRatio.lte(_leverageRatioCeiling)) {
          const premium = await riskPremiumCalculator.calculatePremium(
            _expirationTimestamp,
            protectionAmount,
            protectionBuyerApy,
            leverageRatio,
            _poolParams
          );
          leverageRatio = leverageRatio.add(parseEther("0.005"));
          protectionAmount = protectionAmount.add(_protectionAmt);
          protectionBuyerApy = protectionBuyerApy.add(parseEther("0.01"));
          console.log(`Premium: ${formatEther(premium)}`);
        }
      });
    });
  });
};

export { testRiskPremiumCalculator };
