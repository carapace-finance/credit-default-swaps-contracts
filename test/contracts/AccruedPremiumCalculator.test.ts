import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { parseEther, formatEther } from "ethers/lib/utils";
import { AccruedPremiumCalculator } from "../../typechain-types/contracts/libraries/AccruedPremiumCalculator";

const testAccruedPremiumCalculator: Function = (
  accruedPremiumCalculator: AccruedPremiumCalculator
) => {
  describe("AccruedPremiumCalculator", () => {
    const _curvature: BigNumber = parseEther("0.05");
    const _leverageRatioFloor: BigNumber = parseEther("0.1");
    const _leverageRatioCeiling: BigNumber = parseEther("0.2");
    const _leverageRatioBuffer: BigNumber = parseEther("0.05");
    const _protectionAmt = 1000000; // 1M
    const _annualPremiumRate = 0.04; // 4% annual rate
    const _protection_duration_in_days = 180;
    const _premiumPerDay = (_annualPremiumRate * _protectionAmt) / 365;
    const _totalPremium = parseEther(
      (_premiumPerDay * _protection_duration_in_days).toString()
    );
    const _currentLeverageRatio = parseEther("0.14");

    let K: BigNumber;
    let lambda: BigNumber;

    before(async () => {
      const KAndLamda = await accruedPremiumCalculator.calculateKAndLambda(
        _totalPremium,
        _protection_duration_in_days,
        _currentLeverageRatio,
        _leverageRatioFloor,
        _leverageRatioCeiling,
        _curvature,
        _leverageRatioBuffer
      );
      K = KAndLamda[0];
      lambda = KAndLamda[1];
    });

    describe("calculateRiskFactor", () => {
      it("... calculates correct risk factor", async () => {
        const riskFactor = await accruedPremiumCalculator.calculateRiskFactor(
          _currentLeverageRatio,
          _leverageRatioFloor,
          _leverageRatioCeiling,
          _leverageRatioBuffer,
          _curvature
        );
        expect(riskFactor).to.be.eq(parseEther("-0.55"));
      });

      it("... calculates risk factor without underflow/overflow for range 0.1 to 0.2", async () => {
        const step = parseEther("0.005");
        let leverageRatio = _leverageRatioFloor;
        while (leverageRatio.lte(_leverageRatioCeiling)) {
          await accruedPremiumCalculator.calculateRiskFactor(
            leverageRatio,
            _leverageRatioFloor,
            _leverageRatioCeiling,
            _leverageRatioBuffer,
            _curvature
          );
          leverageRatio = leverageRatio.add(step);

          // TODO: discuss what should happen when denominator is zero in risk factor calculation
          if (leverageRatio.eq(parseEther("0.15"))) {
            // skip 0.15 leverage ratio step
            leverageRatio = leverageRatio.add(step);
            continue;
          }
        }
        expect(true).to.be.true;
      });
    });

    describe("calculateKAndLambda", () => {
      it("... calculates correct K and lambda", async () => {
        expect(K).to.be.lt(parseEther("-63309.5"));
        expect(K).to.be.gt(parseEther("-63309.6"));

        expect(lambda).to.be.lt(parseEther("-0.0015"));
        expect(lambda).to.be.gt(parseEther("-0.0016"));
      });

      it("... calculates K & lambda without underflow/overflow for range 0.1 to 0.2", async () => {
        let leverageRatio = _leverageRatioFloor;
        while (leverageRatio.lte(_leverageRatioCeiling)) {
          await accruedPremiumCalculator.calculateKAndLambda(
            _totalPremium,
            _protection_duration_in_days,
            leverageRatio,
            _leverageRatioFloor,
            _leverageRatioCeiling,
            _leverageRatioBuffer,
            _curvature
          );
          leverageRatio = leverageRatio.add(parseEther("0.005"));

          // TODO: discuss what should happen when denominator is zero in risk factor calculation
          if (leverageRatio.eq(parseEther("0.15"))) {
            // skip 0.15 leverage ratio step
            leverageRatio = leverageRatio.add(parseEther("0.005"));
            continue;
          }
        }
        expect(true).to.be.true;
      });
    });

    describe("calculateAccruedPremium", () => {
      it("... calculates correct accrued premium for a period from day 0 to day 180", async () => {
        const accruedPremium =
          await accruedPremiumCalculator.calculateAccruedPremium(
            0 * 86400, // start time
            _protection_duration_in_days * 86400, // end time
            K,
            lambda
          );

        // accrued premium for a period from day 0 to day 180 should match to total premium
        expect(accruedPremium).to.equal(_totalPremium);
      });

      it("... calculates correct accrued premium for a period from day 0 to day 1", async () => {
        // accrued premium for a period from day 0 to day 1
        const accruedPremium =
          await accruedPremiumCalculator.calculateAccruedPremium(
            0 * 86400, // start time
            1 * 86400, // end time
            K,
            lambda
          );

        expect(accruedPremium).to.be.gt(parseEther("95.469"));
        expect(accruedPremium).to.be.lt(parseEther("95.47"));
      });

      it("... calculates correct accrued premium for a period from day 8 to day 10", async () => {
        // accrued premium for a period from day 0 to day 1
        const accruedPremium =
          await accruedPremiumCalculator.calculateAccruedPremium(
            8 * 86400, // start time
            10 * 86400, // end time
            K,
            lambda
          );

        expect(accruedPremium).to.be.gt(parseEther("193.4011"));
        expect(accruedPremium).to.be.lt(parseEther("193.4012"));
      });

      it("... calculates correct accrued premium for a period from second 100 to second 200", async () => {
        const accruedPremium =
          await accruedPremiumCalculator.calculateAccruedPremium(
            100, // start time
            200, // end time
            K,
            lambda
          );

        console.log("Accrued premium = ", formatEther(accruedPremium));
        expect(accruedPremium).to.be.gt(parseEther("0.11041"));
        expect(accruedPremium).to.be.lt(parseEther("0.12"));
      });
    });
  });
};

export { testAccruedPremiumCalculator };
