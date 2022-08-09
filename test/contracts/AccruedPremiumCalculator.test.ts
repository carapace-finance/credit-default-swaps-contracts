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
            const _currentLeverageRatio = parseEther("0.14");

            let K: BigNumber;
            let lambda: BigNumber;

            before(async () => {
                const KAndLamda = await accruedPremiumCalculator.calculateKAndLambda(
                    _totalPremium,
                    _protection_duration_in_days,
                    _currentLeverageRatio,
                    _curvature,
                    _minLeverageRatio,
                    _maxLeverageRatio
                );
                K = KAndLamda[0];
                lambda = KAndLamda[1];
            });
            it("... calculates correct accrued premium for a period from day 0 to day 180", async () => {
                
                // console.log("Premium = ", formatEther(_premium));
                const accruedPremium = await accruedPremiumCalculator.calculateAccruedPremium(
                    0 * 86400,  // start time
                    _protection_duration_in_days * 86400,    // end time
                    K,
                    lambda
                );

                // console.log("Accrued premium = ", formatEther(accruedPremium));
                // accrued premium for a period from day 0 to day 180 should match to total premium
                expect(accruedPremium).to.equal(_totalPremium);
            });

            it("... calculates correct accrued premium for a period from day 0 to day 1", async () => {
                // accrued premium for a period from day 0 to day 1
                // console.log("Premium = ", formatEther(_premium));
                const accruedPremium = await accruedPremiumCalculator.calculateAccruedPremium(
                    0 * 86400,  // start time
                    1 * 86400,  // end time
                    K,
                    lambda
                );

                // console.log("Accrued premium = ", formatEther(accruedPremium));
                expect(accruedPremium).to.be.gt(parseEther("95.469"));
                expect(accruedPremium).to.be.lt(parseEther("95.47"));
            });

            it("... calculates correct accrued premium for a period from second 100 to second 200", async () => {
                // console.log("Premium = ", formatEther(_premium));
                const accruedPremium = await accruedPremiumCalculator.calculateAccruedPremium(
                    100,  // start time
                    200,  // end time
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