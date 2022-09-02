import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { parseEther } from "ethers/lib/utils";
import { RiskFactorCalculator } from "../../typechain-types/contracts/libraries/RiskFactorCalculator";

const testRiskFactorCalculator: Function = (
  riskFactorCalculator: RiskFactorCalculator
) => {
  describe("RiskFactorCalculator", () => {
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

    describe("calculateRiskFactor", () => {
      it("... calculates correct risk factor", async () => {
        const riskFactor = await riskFactorCalculator.calculateRiskFactor(
          _currentLeverageRatio,
          _leverageRatioFloor,
          _leverageRatioCeiling,
          _leverageRatioBuffer,
          _curvature
        );
        expect(riskFactor).to.be.eq(parseEther("0.061111111111111111"));
      });

      it("... calculates risk factor without underflow/overflow for range 0.05 to 0.25", async () => {
        const step = parseEther("0.005");
        let leverageRatio = _leverageRatioFloor;
        while (leverageRatio.lte(_leverageRatioCeiling)) {
          await riskFactorCalculator.calculateRiskFactor(
            leverageRatio,
            _leverageRatioFloor,
            _leverageRatioCeiling,
            _leverageRatioBuffer,
            _curvature
          );
          leverageRatio = leverageRatio.add(step);
        }
        expect(true).to.be.true;
      });
    });
  });
};

export { testRiskFactorCalculator };
