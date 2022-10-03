import { expect } from "chai";
import { Signer } from "ethers/lib/ethers";
import { parseEther } from "ethers/lib/utils";
import { ZERO_ADDRESS } from "../../test/utils/constants";
import {
  IReferenceLendingPools,
  ReferenceLendingPools
} from "../../typechain-types/contracts/core/pool/ReferenceLendingPools";
import { ReferenceLendingPoolsFactory } from "../../typechain-types/contracts/core/ReferenceLendingPoolsFactory";
import {
  getDaysInSeconds,
  getLatestBlockTimestamp,
  moveForwardTime
} from "../utils/time";
import { parseUSDC } from "../utils/usdc";

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
    let deployerAddress: string;
    let _implementationDeployerAddress: string;

    before(async () => {
      deployerAddress = await deployer.getAddress();
      _implementationDeployerAddress =
        await implementationDeployer.getAddress();
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
              deployerAddress,
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
          expect(owner).to.equal(deployerAddress);
        });

        it("...should disable initialize after creation", async () => {
          await expect(
            referenceLendingPoolsInstance.initialize(
              deployerAddress,
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
            .withArgs(_implementationDeployerAddress, deployerAddress);
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
      });

      describe("canBuyProtection", async () => {
        let _purchaseParams: IReferenceLendingPools.ProtectionPurchaseParamsStruct;
        const BUYER1 = "0x12c2cfda0a51fe2a68e443868bcbf3d6f6e2dda2";
        const BUYER2 = "0x10a590f528eff3d5de18c90da6e03a4acdde3a7d";

        before("set up", async () => {
          _purchaseParams = {
            lendingPoolAddress: LENDING_POOL_3,
            nftLpTokenId: 714, // see: https://lark.market/tokenDetail?tokenId=714
            protectionAmount: parseUSDC("100"),
            protectionExpirationTimestamp: 1740068036
          };
        });

        it("...should return true when protection purchase limit is not expired & amount is valid", async () => {
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams
            )
          ).to.be.eq(true);
        });

        it("...should return false when protection purchase limit is not expired but amount is higher than principal", async () => {
          // principal amount is 10,270.41 USDC
          _purchaseParams.protectionAmount = parseUSDC("11000");
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams
            )
          ).to.be.eq(false);
        });

        it("...should return false when the buyer does not own the NFT specified", async () => {
          _purchaseParams.nftLpTokenId = 100;
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams
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
              _purchaseParams
            )
          ).to.be.eq(false);
        });

        it("...should return false when protection purchase limit is expired", async () => {
          await moveForwardTime(getDaysInSeconds(11));
          expect(
            await referenceLendingPoolsInstance.canBuyProtection(
              _implementationDeployerAddress,
              _purchaseParams
            )
          ).to.be.eq(false);
        });

        it("...should revert when a pool is not added/supported", async () => {
          _purchaseParams.lendingPoolAddress =
            "0xaa2ccc5547f64c5dffd0a624eb4af2543a67ba65";
          await expect(
            referenceLendingPoolsInstance.canBuyProtection(
              BUYER1,
              _purchaseParams
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
    });
  });
};

export { testReferenceLendingPools };
