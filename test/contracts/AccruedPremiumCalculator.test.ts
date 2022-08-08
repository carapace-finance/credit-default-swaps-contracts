import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { parseEther,formatEther } from "ethers/lib/utils";
import { AccruedPremiumCalculator } from "../../typechain-types/contracts/libraries/AccruedPremiumCalculator";

const testAccruedPremiumCalculator: Function = (
    accruedPremiumCalculator: AccruedPremiumCalculator
) => {
    describe("AccruedPremiumCalculator", () => {
        describe("calculateAccruedPremium", () => {
            const _curvature: BigNumber = parseEther("0.05");
            const _minLeverageRatio: BigNumber = parseEther("0.1");
            const _maxLeverageRatio: BigNumber = parseEther("0.2");
            const _protectionAmt = 1000000;  // 1M
            const _annualPremiumRate = 0.04; // 4% annual rate
            const _protection_duration_in_days = 180;
            const _premiumPerDay = (_annualPremiumRate * _protectionAmt)/365;
            const _totalPremium = parseEther((_premiumPerDay * _protection_duration_in_days).toString());                
            const _currentLeverageRatio = parseEther("0.15");

            it("... calculates correct accrued premium for a period from day 0 to day 180", async () => {
                // console.log("Premium = ", formatEther(_premium));
                const accruedPremium = await accruedPremiumCalculator.calculateAccruedPremium(
                    _totalPremium,
                    _protection_duration_in_days,
                    0 * 86400,  // start time
                    _protection_duration_in_days * 86400,    // end time
                    _currentLeverageRatio,
                    _curvature,
                    _minLeverageRatio,
                    _maxLeverageRatio
                );

                // console.log("Accrued premium = ", formatEther(accruedPremium));
                // accrued premium for a period from day 0 to day 180 should match to total premium
                expect(accruedPremium).to.equal(_totalPremium);
            });

            it("... calculates correct accrued premium for a period from day 0 to day 1", async () => {
                // accrued premium for a period from day 0 to day 1
                // console.log("Premium = ", formatEther(_premium));
                const accruedPremium = await accruedPremiumCalculator.calculateAccruedPremium(
                    _totalPremium,
                    _protection_duration_in_days,
                    0 * 86400,  // start time
                    1 * 86400,  // end time
                    _currentLeverageRatio,
                    _curvature,
                    _minLeverageRatio,
                    _maxLeverageRatio
                );

                // console.log("Accrued premium = ", formatEther(accruedPremium));
                expect(accruedPremium).to.be.gt(parseEther("110.938"));
            });

            it("... calculates correct accrued premium for a period from second 100 to second 200", async () => {
                // console.log("Premium = ", formatEther(_premium));
                const accruedPremium = await accruedPremiumCalculator.calculateAccruedPremium(
                    _totalPremium,
                    _protection_duration_in_days,
                    100,  // start time
                    200,  // end time
                    _currentLeverageRatio,
                    _curvature,
                    _minLeverageRatio,
                    _maxLeverageRatio
                );

                console.log("Accrued premium = ", formatEther(accruedPremium));
                expect(accruedPremium).to.be.gt(parseEther("0.128409"));
            });
        });
    });
};

export { testAccruedPremiumCalculator };