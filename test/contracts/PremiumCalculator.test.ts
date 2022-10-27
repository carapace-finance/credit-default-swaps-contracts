import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { parseEther, formatEther } from "ethers/lib/utils";
import {
  PoolParamsStruct,
  PoolCycleParamsStruct
} from "../../typechain-types/contracts/interfaces/IPool";
import { parseUSDC } from "../utils/usdc";

import { PremiumCalculator } from "../../typechain-types/contracts/core/PremiumCalculator";
import { getDaysInSeconds, getUnixTimestampAheadByDays } from "../utils/time";

const testPremiumCalculator: Function = (
  premiumCalculator: PremiumCalculator
) => {
  describe("PremiumCalculator", () => {
    const _curvature: BigNumber = parseEther("0.05");
    const _leverageRatioFloor: BigNumber = parseEther("0.1");
    const _leverageRatioCeiling: BigNumber = parseEther("0.2");
    const _leverageRatioBuffer: BigNumber = parseEther("0.05");
    const _protectionAmt = parseEther("100000"); // 100k
    const _currentLeverageRatio = parseEther("0.15"); // 15%
    const _protectionBuyerApy = parseEther("0.17"); // 17%
    const poolCycleParams: PoolCycleParamsStruct = {
      openCycleDuration: BigNumber.from(10 * 86400), // 10 days
      cycleDuration: BigNumber.from(30 * 86400) // 30 days
    };
    const _minRequiredCapital = parseUSDC("10000");
    const _minRequiredProtection = parseUSDC("20000");
    const _poolParams: PoolParamsStruct = {
      leverageRatioFloor: _leverageRatioFloor,
      leverageRatioCeiling: _leverageRatioCeiling,
      leverageRatioBuffer: _leverageRatioBuffer,
      minRequiredCapital: _minRequiredCapital,
      minRequiredProtection: _minRequiredProtection,
      curvature: _curvature,
      minCarapaceRiskPremiumPercent: parseEther("0.02"), // 2%
      underlyingRiskPremiumPercent: parseEther("0.1"), // 10%
      minProtectionDurationInSeconds: getDaysInSeconds(10),
      poolCycleParams: poolCycleParams
    };

    describe("calculatePremium", () => {
      const _totalCapital = parseUSDC("15000");
      const _totalProtection = parseUSDC("100000");

      it("... calculates correct premium amount for a period of 180 days", async () => {
        const _expirationTimestamp = await getUnixTimestampAheadByDays(180);
        const premiumAndMinPremiumFlag =
          await premiumCalculator.calculatePremium(
            _expirationTimestamp,
            _protectionAmt,
            _protectionBuyerApy,
            _currentLeverageRatio,
            _totalCapital,
            _totalProtection,
            _poolParams
          );

        expect(premiumAndMinPremiumFlag[0])
          .to.be.gt(parseEther("3271.8265"))
          .and.lt(parseEther("3271.8266"));
      });

      it("... calculates correct premium amount for a period of 365 days", async () => {
        const _expirationTimestamp = await getUnixTimestampAheadByDays(365);

        const premiumAndMinPremiumFlag =
          await premiumCalculator.calculatePremium(
            _expirationTimestamp,
            _protectionAmt,
            _protectionBuyerApy,
            _currentLeverageRatio,
            _totalCapital,
            _totalProtection,
            _poolParams
          );

        expect(premiumAndMinPremiumFlag[0])
          .to.be.gt(parseEther("6572.8151"))
          .and.lt(parseEther("6572.8152"));
      });

      it("... calculates premium amount without overflow/underflow for a range of leverage ratio from 0.1 to 0.2", async () => {
        const _expirationTimestamp = await getUnixTimestampAheadByDays(365 * 2); // 2 years

        let leverageRatio = _leverageRatioFloor;
        let protectionAmount = _protectionAmt;
        let protectionBuyerApy = parseEther("0.1");
        while (leverageRatio.lte(_leverageRatioCeiling)) {
          await premiumCalculator.calculatePremium(
            _expirationTimestamp,
            protectionAmount,
            protectionBuyerApy,
            leverageRatio,
            _totalCapital,
            _totalProtection,
            _poolParams
          );
          leverageRatio = leverageRatio.add(parseEther("0.005"));
          protectionAmount = protectionAmount.add(_protectionAmt);
          protectionBuyerApy = protectionBuyerApy.add(parseEther("0.01"));
        }
      });
    });

    describe("calculatePremium with min carapace premium rate", () => {
      it("... calculates correct premium amount when leverage ratio is less than floor", async () => {
        const _totalCapital = parseUSDC("500000");
        const _totalProtection = parseUSDC("100000000");
        const _expirationTimestamp = await getUnixTimestampAheadByDays(180);

        const premiumAndMinPremiumFlag =
          await premiumCalculator.calculatePremium(
            _expirationTimestamp,
            _protectionAmt,
            _protectionBuyerApy,
            _leverageRatioFloor.sub(parseEther("0.05")), // leverage ratio(0.05) is less than floor
            _totalCapital,
            _totalProtection,
            _poolParams
          );

        expect(premiumAndMinPremiumFlag[0])
          .to.be.gt(parseEther("2837.8052"))
          .and.lt(parseEther("2837.8053"));
      });

      it("... calculates correct premium amount when leverage ratio is higher than ceiling", async () => {
        const _totalCapital = parseUSDC("15000");
        const _totalProtection = parseUSDC("60000");
        const _expirationTimestamp = await getUnixTimestampAheadByDays(180);

        const premiumAndMinPremiumFlag =
          await premiumCalculator.calculatePremium(
            _expirationTimestamp,
            _protectionAmt,
            _protectionBuyerApy,
            _leverageRatioCeiling.add(parseEther("0.05")), // leverage ratio(0.25) is higher than ceiling
            _totalCapital,
            _totalProtection,
            _poolParams
          );

        expect(premiumAndMinPremiumFlag[0])
          .to.be.gt(parseEther("2837.8052"))
          .and.lt(parseEther("2837.8053"));
      });

      it("... calculates correct premium amount when total capital is lower than min required capital", async () => {
        const _totalCapital = _minRequiredCapital.sub(parseUSDC("1"));
        const _totalProtection = _minRequiredProtection.add(parseUSDC("1000"));
        const _expirationTimestamp = await getUnixTimestampAheadByDays(180);

        const premiumAndMinPremiumFlag =
          await premiumCalculator.calculatePremium(
            _expirationTimestamp,
            _protectionAmt,
            _protectionBuyerApy,
            0,
            _totalCapital,
            _totalProtection,
            _poolParams
          );

        expect(premiumAndMinPremiumFlag[0])
          .to.be.gt(parseEther("2837.8052"))
          .and.lt(parseEther("2837.8053"));
      });

      it("... calculates correct premium amount when total protection is lower than min required protection", async () => {
        const _totalCapital = _minRequiredCapital.add(parseUSDC("1"));
        const _totalProtection = _minRequiredProtection.sub(parseUSDC("1000"));
        const _expirationTimestamp = await getUnixTimestampAheadByDays(180);

        const premiumAndMinPremiumFlag =
          await premiumCalculator.calculatePremium(
            _expirationTimestamp,
            _protectionAmt,
            _protectionBuyerApy,
            0,
            _totalCapital,
            _totalProtection,
            _poolParams
          );

        expect(premiumAndMinPremiumFlag[0])
          .to.be.gt(parseEther("2837.8052"))
          .and.lt(parseEther("2837.8053"));
      });
    });
  });
};

export { testPremiumCalculator };
