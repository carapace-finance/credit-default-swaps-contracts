import { expect } from "chai";
import { Signer } from "ethers/lib/ethers";
import { parseEther } from "ethers/lib/utils";
import { ZERO_ADDRESS } from "../../test/utils/constants";
import { ProtectionPurchaseParamsStruct } from "../../typechain-types/contracts/interfaces/IReferenceLendingPools";
import { ReferenceLendingPools } from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ReferenceLendingPoolsFactory } from "../../typechain-types/contracts/core/ReferenceLendingPoolsFactory";
import {
  getDaysInSeconds,
  getLatestBlockTimestamp,
  moveForwardTime,
  setNextBlockTimestamp
} from "../utils/time";
import { parseUSDC } from "../utils/usdc";
import { network } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";

const LENDING_POOL_3 = "0x89d7c618a4eef3065da8ad684859a547548e6169";

const testReferenceLendingPools: Function = (
  deployer: Signer,
  implementationDeployer: Signer,
  referenceLendingPoolsImplementation: ReferenceLendingPools,
  referenceLendingPoolsInstance: ReferenceLendingPools,
  referenceLendingPoolsFactoryInstance: ReferenceLendingPoolsFactory,
  addedLendingPools: string[]
) => {
  describe("ReferenceLendingPools", async () => {
    let _deployerAddress: string;
    let _implementationDeployerAddress: string;
    let _expectedLendingPools: string[];
    let _snapshotId: string;

    async function revertToSnapshot(_snapshotId: string) {
      expect(await network.provider.send("evm_revert", [_snapshotId])).to.eq(
        true
      );
    }

    before(async () => {
      _deployerAddress = await deployer.getAddress();
      _implementationDeployerAddress =
        await implementationDeployer.getAddress();
      _snapshotId = await network.provider.send("evm_snapshot", []);
    });

    after(async () => {
      // Some specs move time forward, revert the state to the snapshot
      await revertToSnapshot(_snapshotId);
    });

    describe("Implementation", async () => {
      describe("constructor", async () => {
        it("...should set the correct owner on construction", async () => {
          const owner: string =
            await referenceLendingPoolsImplementation.owner();
          expect(owner).to.equal(_implementationDeployerAddress);
        });

        it("...should disable initialize after construction", async () => {
          await expect(
            referenceLendingPoolsImplementation.initialize(
              _deployerAddress,
              [],
              [],
              []
            )
          ).to.be.revertedWith(
            "Initializable: contract is already initialized"
          );
        });

        it("...should not have any state", async () => {
          const referenceLendingPoolInfo =
            await referenceLendingPoolsImplementation.referenceLendingPools(
              "0xb26b42dd5771689d0a7faeea32825ff9710b9c11"
            );
          expect(referenceLendingPoolInfo.addedTimestamp).to.equal(0);

          expect(
            await referenceLendingPoolsImplementation.lendingProtocolAdapters(0)
          ).to.equal(ZERO_ADDRESS);
        });
      });
    });

    describe("Minimal Proxy", async () => {
      it("...and implementation are different instances", async () => {
        expect(referenceLendingPoolsInstance.address).to.not.equal(
          referenceLendingPoolsImplementation.address
        );
      });

      describe("initialize", async () => {
        it("...should set the correct owner on construction", async () => {
          const owner: string = await referenceLendingPoolsInstance.owner();
          expect(owner).to.equal(_deployerAddress);

          _expectedLendingPools =
            await referenceLendingPoolsInstance.getLendingPools();
        });

        it("...should have added lending pools in the basket", async () => {
          expect(_expectedLendingPools.length).to.equal(
            addedLendingPools.length
          );

          for (let i = 0; i < _expectedLendingPools.length; i++) {
            expect(_expectedLendingPools[i].toLowerCase()).to.equal(
              addedLendingPools[i].toLowerCase()
            );
          }
        });

        it("...should disable initialize after creation", async () => {
          await expect(
            referenceLendingPoolsInstance.initialize(
              _deployerAddress,
              [],
              [],
              []
            )
          ).to.be.revertedWith(
            "Initializable: contract is already initialized"
          );
        });

        it("...should have 2 lending pools added", async () => {
          const latestTimestamp = await getLatestBlockTimestamp();
          const purchaseLimitTimestamp = latestTimestamp + getDaysInSeconds(90);

          addedLendingPools.forEach(async (lendingPool) => {
            const lendingPoolInfo =
              await referenceLendingPoolsInstance.referenceLendingPools(
                lendingPool
              );
            expect(lendingPoolInfo.protocol).to.be.eq(0); // GoldfinchV2
            expect(lendingPoolInfo.addedTimestamp).to.be.eq(latestTimestamp);
            expect(lendingPoolInfo.protectionPurchaseLimitTimestamp).to.be.eq(
              purchaseLimitTimestamp
            );
          });
        });

        it("...should have Goldfinch adapter created", async () => {
          expect(
            await referenceLendingPoolsInstance.lendingProtocolAdapters(0)
          ).to.not.equal(ZERO_ADDRESS);
        });

        it("...should not have any other adapter created", async () => {
          await expect(referenceLendingPoolsInstance.lendingProtocolAdapters(1))
            .to.be.reverted;
        });

        it("...should transfer ownership during initialization", async () => {
          expect(
            await referenceLendingPoolsFactoryInstance.createReferenceLendingPools(
              [],
              [],
              []
            )
          )
            .emit(referenceLendingPoolsInstance, "OwnershipTransferred")
            .withArgs(_implementationDeployerAddress, _deployerAddress);
        });
      });

      describe("assessState before adding a lending pool", async () => {
        it("...should return 2 pools & statuses", async () => {
          const lendingPoolsAndStatuses =
            await referenceLendingPoolsInstance.assessState();
          const lendingPools: string[] = lendingPoolsAndStatuses[0];
          const statuses: number[] = lendingPoolsAndStatuses[1];

          expect(lendingPools).to.have.length(2);
          expect(statuses).to.have.length(2);

          for (let i = 0; i < 2; i++) {
            expect(lendingPools[i].toLowerCase()).to.be.eq(
              addedLendingPools[i].toLowerCase()
            );
            expect(statuses[i]).to.be.eq(1); // Active
          }
        });
      });

      describe("addReferenceLendingPool", async () => {
        it("...should revert when not called by owner", async () => {
          await expect(
            referenceLendingPoolsInstance
              .connect(implementationDeployer)
              .addReferenceLendingPool(ZERO_ADDRESS, 0, 0)
          ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("...should revert when new pool is added with zero address by owner", async () => {
          await expect(
            referenceLendingPoolsInstance
              .connect(deployer)
              .addReferenceLendingPool(ZERO_ADDRESS, [0], [10])
          ).to.be.revertedWith("ReferenceLendingPoolIsZeroAddress");
        });

        it("...should revert when existing pool is added again by owner", async () => {
          const lendingPool = addedLendingPools[0];
          await expect(
            referenceLendingPoolsInstance
              .connect(deployer)
              .addReferenceLendingPool(lendingPool, [0], [10])
          ).to.be.revertedWith("ReferenceLendingPoolAlreadyAdded");
        });

        it("...should revert when new pool is added with unsupported protocol by owner", async () => {
          await expect(
            referenceLendingPoolsInstance
              .connect(deployer)
              .addReferenceLendingPool(LENDING_POOL_3, [1], [10])
          ).to.be.revertedWith;
        });

        it("...should revert when expired(repaid) pool is added by owner", async () => {
          // repaid pool: https://app.goldfinch.finance/pools/0xc13465ce9ae3aa184eb536f04fdc3f54d2def277
          await expect(
            referenceLendingPoolsInstance
              .connect(deployer)
              .addReferenceLendingPool(
                "0xc13465ce9ae3aa184eb536f04fdc3f54d2def277",
                [0],
                [10]
              )
          ).to.be.revertedWith("ReferenceLendingPoolIsNotActive");
        });

        // Could not find defaulted lending pool
        it("...should revert when defaulted pool is added by owner", async () => {
          await expect(
            referenceLendingPoolsInstance
              .connect(deployer)
              .addReferenceLendingPool(
                "0xc13465ce9ae3aa184eb536f04fdc3f54d2def277",
                [0],
                [10]
              )
          ).to.be.revertedWith("ReferenceLendingPoolIsNotActive");
        });

        it("...should succeed when a new pool is added by owner", async () => {
          await expect(
            referenceLendingPoolsInstance
              .connect(deployer)
              .addReferenceLendingPool(LENDING_POOL_3, 0, 10)
          ).to.emit(referenceLendingPoolsInstance, "ReferenceLendingPoolAdded");
        });
      });

      describe("assessState after adding a lending pool", async () => {
        it("...should return 3 pools & statuses", async () => {
          const lendingPoolsAndStatuses =
            await referenceLendingPoolsInstance.assessState();
          const lendingPools: string[] = lendingPoolsAndStatuses[0];
          const statuses: number[] = lendingPoolsAndStatuses[1];
          const expectedLendingPools =
            await referenceLendingPoolsInstance.getLendingPools();
          expect(lendingPools).to.have.length(expectedLendingPools.length);
          expect(statuses).to.have.length(expectedLendingPools.length);

          for (let i = 0; i < expectedLendingPools.length; i++) {
            expect(lendingPools[i].toLowerCase()).to.be.eq(
              expectedLendingPools[i].toLowerCase()
            );
            expect(statuses[i]).to.be.eq(1); // Active
          }
        });
      });

      describe("canBuyProtection", async () => {
        let _purchaseParams: ProtectionPurchaseParamsStruct;
        const BUYER1 = "0x12c2cfda0a51fe2a68e443868bcbf3d6f6e2dda2";
        const BUYER2 = "0x10a590f528eff3d5de18c90da6e03a4acdde3a7d";
        let _buyerHasActiveProtection: boolean;

        before("set up", async () => {
          _buyerHasActiveProtection = false;
          _purchaseParams = {
            lendingPoolAddress: LENDING_POOL_3,
            nftLpTokenId: 714, // see: https://lark.market/tokenDetail?tokenId=714
            protectionAmount: parseUSDC("100"),
            protectionDurationInSeconds: getDaysInSeconds(30)
          };
        });

        it("...should return true when protection purchase limit is not expired & amount is valid", async () => {
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams,
              _buyerHasActiveProtection
            )
          ).to.be.eq(true);
        });

        it("...should return false when protection purchase limit is not expired but amount is higher than principal", async () => {
          // principal amount is 10,270.41 USDC
          _purchaseParams.protectionAmount = parseUSDC("11000");
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams,
              _buyerHasActiveProtection
            )
          ).to.be.eq(false);
        });

        it("...should return false when the buyer does not own the NFT specified", async () => {
          _purchaseParams.nftLpTokenId = 100;
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams,
              _buyerHasActiveProtection
            )
          ).to.be.eq(false);
        });

        it("...should return false when the buyer owns the NFT for different pool", async () => {
          // see: https://lark.market/tokenDetail?tokenId=142
          // Buyer owns this token, but pool for this token is 0x57686612c601cb5213b01aa8e80afeb24bbd01df
          _purchaseParams.nftLpTokenId = 142;

          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              BUYER2,
              _purchaseParams,
              _buyerHasActiveProtection
            )
          ).to.be.eq(false);
        });

        it("...should return false when protection purchase limit is expired", async () => {
          await moveForwardTime(getDaysInSeconds(11));
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              _implementationDeployerAddress,
              _purchaseParams,
              _buyerHasActiveProtection
            )
          ).to.be.eq(false);
        });

        it("...should return true when protection purchase limit is expired but buyer has active protection", async () => {
          _buyerHasActiveProtection = true;
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              _implementationDeployerAddress,
              _purchaseParams,
              _buyerHasActiveProtection
            )
          ).to.be.eq(false);
        });

        it("...should revert when a pool is not added/supported", async () => {
          _purchaseParams.lendingPoolAddress =
            "0xaa2ccc5547f64c5dffd0a624eb4af2543a67ba65";
          await expect(
            referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams,
              _buyerHasActiveProtection
            )
          ).to.be.revertedWith("ReferenceLendingPoolNotSupported");
        });
      });

      describe("calculateProtectionBuyerAPR", () => {
        it("...should return the correct interest rate", async () => {
          // see USDC APY: https://app.goldfinch.finance/pools/0x89d7c618a4eef3065da8ad684859a547548e6169
          expect(
            await referenceLendingPoolsInstance.calculateProtectionBuyerAPR(
              LENDING_POOL_3
            )
          ).to.eq(parseEther("0.17"));
        });

        it("...should revert when a pool is not added/supported", async () => {
          await expect(
            referenceLendingPoolsInstance.calculateProtectionBuyerAPR(
              "0xaa2ccc5547f64c5dffd0a624eb4af2543a67ba65"
            )
          ).to.be.revertedWith("ReferenceLendingPoolNotSupported");
        });
      });

      describe("calculateRemainingPrincipal", () => {
        it("...should return the correct remaining principal", async () => {
          // token info: pool,                           tranche, principal,    principalRedeemed, interestRedeemed
          // 0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf, 2,       35000000000,  0,                 2400000000
          expect(
            await referenceLendingPoolsInstance.calculateRemainingPrincipal(
              "0xd09a57127bc40d680be7cb061c2a6629fe71abef",
              "0xcb726f13479963934e91b6f34b6e87ec69c21bb9",
              615
            )
          ).to.eq(parseUSDC("35000"));
        });

        it("...should return the 0 remaining principal for non-owner", async () => {
          // lender doesn't own the NFT
          expect(
            await referenceLendingPoolsInstance.calculateRemainingPrincipal(
              "0xd09a57127bc40d680be7cb061c2a6629fe71abef",
              "0xcb726f13479963934e91b6f34b6e87ec69c21bb9",
              590
            )
          ).to.eq(0);
        });
      });

      // This test spec should be last as it sets exact block timestamp and then moves time forward
      describe("getLendingPoolStatus", async () => {
        it("...should return correct status for non-existing pool", async () => {
          expect(
            await referenceLendingPoolsInstance.getLendingPoolStatus(
              ZERO_ADDRESS
            )
          ).to.be.eq(0); // NotSupported
        });

        it("...should return correct status for active pool", async () => {
          expect(
            await referenceLendingPoolsInstance.getLendingPoolStatus(
              LENDING_POOL_3
            )
          ).to.be.eq(1); // Active
        });

        it("...should return active when payment is not late", async () => {
          // Move time forward by 30 days from last payment timestamp
          const lastPaymentTimestamp =
            await referenceLendingPoolsInstance.getLatestPaymentTimestamp(
              "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
            );
          await setNextBlockTimestamp(
            lastPaymentTimestamp.add(getDaysInSeconds(30))
          );

          // This means, payment is still not late and should return false
          expect(
            await referenceLendingPoolsInstance.getLendingPoolStatus(
              "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
            )
          ).to.eq(1); // Active
        });

        it("...should return LateWithinGracePeriod when payment is late but within grace period", async () => {
          // Move time forward by 1 second
          await moveForwardTime(BigNumber.from(1));

          // Lending pool is late but within grace period, so should return LateWithinGracePeriod status
          expect(
            await referenceLendingPoolsInstance.getLendingPoolStatus(
              "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
            )
          ).to.eq(3); // LateWithinGracePeriod
        });

        it("...should return false when payment is late and after grace period", async () => {
          // Move time forward by one more day
          await moveForwardTime(getDaysInSeconds(1));

          // Lending pool is late and after grace period, so should return Late status
          // Total time elapsed since last payment = 30 days + 1 day + 1 second
          expect(
            await referenceLendingPoolsInstance.getLendingPoolStatus(
              "0xd09a57127BC40D680Be7cb061C2a6629Fe71AbEf"
            )
          ).to.eq(4); // Late
        });
      });
    });
  });
};

export { testReferenceLendingPools };
