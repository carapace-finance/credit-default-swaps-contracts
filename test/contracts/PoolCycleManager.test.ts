import { BigNumber } from "@ethersproject/bignumber";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { assert } from "console";
import { Signer } from "ethers";
import { ethers, upgrades } from "hardhat";
import { PoolCycleManager } from "../../typechain-types/contracts/core/PoolCycleManager";
import { PoolCycleManagerV2 } from "../../typechain-types/contracts/test/PoolCycleManagerV2";
import { ZERO_ADDRESS } from "../utils/constants";
import { moveForwardTime } from "../utils/time";

const testPoolCycleManager: Function = (
  deployer: Signer,
  account1: Signer,
  poolCycleManager: PoolCycleManager,
  contractFactoryAddress: string
) => {
  describe("PoolCycleManager", () => {
    const _poolAddress: string = "0x395326f1418F65F581693de55719c824ad48A367";
    const _secondPoolAddress: string =
      "0x7dA5E231478d5F5ACB45DBC122DE7846b676F715";
    const _openCycleDuration: BigNumber = BigNumber.from(7 * 24 * 60 * 60); // 7 days
    const _cycleDuration: BigNumber = BigNumber.from(30 * 24 * 60 * 60); // 30 days

    describe("implementation", async () => {
      let poolCycleManagerImplementation: PoolCycleManager;

      before(async () => {
        poolCycleManagerImplementation = (await ethers.getContractAt(
          "DefaultStateManager",
          await upgrades.erc1967.getImplementationAddress(
            poolCycleManager.address
          )
        )) as PoolCycleManager;
      });

      it("...should NOT have an owner on construction", async () => {
        expect(await poolCycleManagerImplementation.owner()).to.equal(
          ZERO_ADDRESS
        );
      });

      it("...should disable initialize after construction", async () => {
        await expect(
          poolCycleManagerImplementation.initialize()
        ).to.be.revertedWith("Initializable: contract is already initialized");
      });
    });

    describe("constructor", async () => {
      it("...should be valid instance", async () => {
        expect(poolCycleManager).to.not.equal(undefined);
      });

      it("...should set deployer as on owner", async () => {
        expect(await poolCycleManager.owner()).to.equal(
          await deployer.getAddress()
        );
      });

      it("... should revert when initialize is called 2nd time", async () => {
        await expect(poolCycleManager.initialize()).to.be.revertedWith(
          "Initializable: contract is already initialized"
        );
      });
    });

    describe("setContractFactory", async () => {
      it("...should fail when called by non-owner", async () => {
        await expect(
          poolCycleManager.connect(account1).setContractFactory(ZERO_ADDRESS)
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("...should fail when address is zeo", async () => {
        await expect(
          poolCycleManager.connect(deployer).setContractFactory(ZERO_ADDRESS)
        ).to.be.revertedWith("ZeroContractFactoryAddress");
      });

      it("...should work correctly by owner", async () => {
        expect(await poolCycleManager.contractFactoryAddress()).to.equal(
          contractFactoryAddress
        );

        // Set deployer as contract factory for tests
        await poolCycleManager
          .connect(deployer)
          .setContractFactory(await deployer.getAddress());

        expect(await poolCycleManager.contractFactoryAddress()).to.equal(
          await deployer.getAddress()
        );
      });
    });

    describe("registerPool", async () => {
      it("...should NOT be callable by non-pool-factory address", async () => {
        await expect(
          poolCycleManager
            .connect(account1)
            .registerPool(_poolAddress, _openCycleDuration, _cycleDuration)
        ).to.be.revertedWith(
          `NotContractFactory("${await account1.getAddress()}")`
        );
      });

      it("...should be able callable by only pool factory contract", async () => {
        await expect(
          poolCycleManager
            .connect(deployer)
            .registerPool(_poolAddress, _openCycleDuration, _cycleDuration)
        )
          .to.emit(poolCycleManager, "PoolCycleCreated")
          .withArgs(
            _poolAddress,
            0,
            anyValue,
            _openCycleDuration,
            _cycleDuration
          );
      });

      it("...should NOT be able to register pool twice", async () => {
        await expect(
          poolCycleManager
            .connect(deployer)
            .registerPool(_poolAddress, _openCycleDuration, _cycleDuration)
        ).to.be.revertedWith(`PoolAlreadyRegistered("${_poolAddress}")`);
      });

      it("...should NOT be able to register pool with openCycleDuration > cycleDuration", async () => {
        await expect(
          poolCycleManager
            .connect(deployer)
            .registerPool(
              _secondPoolAddress,
              _openCycleDuration.add(_cycleDuration),
              _cycleDuration
            )
        ).to.be.revertedWith(`InvalidCycleDuration(${_cycleDuration})`);
      });

      it("...should create new cycle for the pool with correct params", async () => {
        await poolCycleManager
          .connect(deployer)
          .registerPool(_secondPoolAddress, _openCycleDuration, _cycleDuration);

        expect(
          await poolCycleManager.getCurrentCycleIndex(_secondPoolAddress)
        ).to.equal(0);
        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(1); // 1 = Open

        const poolCycle = await poolCycleManager.poolCycles(_secondPoolAddress);
        expect(poolCycle.openCycleDuration).to.equal(_openCycleDuration);
        expect(poolCycle.cycleDuration).to.equal(_cycleDuration);
        expect(poolCycle.currentCycleStartTime).to.equal(
          (await ethers.provider.getBlock("latest")).timestamp
        );
      });

      it("...should be able to register multiple pools", async () => {
        // register 3rd pool
        const thirdPoolAddress: string =
          "0xa13c4F4bAea32D953813147FdBB3799CDaB5F641";
        const thirdOpenCycleDuration: BigNumber = BigNumber.from(
          2 * 24 * 60 * 60
        );
        const thirdCycleDuration: BigNumber = BigNumber.from(12 * 24 * 60 * 60);
        await poolCycleManager
          .connect(deployer)
          .registerPool(
            thirdPoolAddress,
            thirdOpenCycleDuration,
            thirdCycleDuration
          );

        expect(
          await poolCycleManager.getCurrentCycleIndex(thirdPoolAddress)
        ).to.equal(0);
        expect(
          await poolCycleManager.getCurrentCycleState(thirdPoolAddress)
        ).to.equal(1); // 1 = Open

        const thirdPoolCycle = await poolCycleManager.poolCycles(
          thirdPoolAddress
        );
        expect(thirdPoolCycle.openCycleDuration).to.equal(
          thirdOpenCycleDuration
        );
        expect(thirdPoolCycle.cycleDuration).to.equal(thirdCycleDuration);
        expect(thirdPoolCycle.currentCycleStartTime).to.equal(
          (await ethers.provider.getBlock("latest")).timestamp
        );

        // register 4th pool
        const fourthPoolAddress: string =
          "0x3d7b7F12eDB3A0A2b9e9efc3EfD25c7455677746";
        const fourthOpenCycleDuration: BigNumber = BigNumber.from(
          5 * 24 * 60 * 60
        );
        const fourthCycleDuration: BigNumber = BigNumber.from(
          15 * 24 * 60 * 60
        );
        await poolCycleManager
          .connect(deployer)
          .registerPool(
            fourthPoolAddress,
            fourthOpenCycleDuration,
            fourthCycleDuration
          );

        expect(
          await poolCycleManager.getCurrentCycleIndex(fourthPoolAddress)
        ).to.equal(0);
        expect(
          await poolCycleManager.getCurrentCycleState(fourthPoolAddress)
        ).to.equal(1); // 1 = Open

        const fourthPoolCycle = await poolCycleManager.poolCycles(
          fourthPoolAddress
        );
        expect(fourthPoolCycle.openCycleDuration).to.equal(
          fourthOpenCycleDuration
        );
        expect(fourthPoolCycle.cycleDuration).to.equal(fourthCycleDuration);
        expect(fourthPoolCycle.currentCycleStartTime).to.equal(
          (await ethers.provider.getBlock("latest")).timestamp
        );
      });
    });

    describe("calculateAndSetPoolCycleState", async () => {
      let cycleStartTime: BigNumber;
      before(async () => {
        cycleStartTime = (await poolCycleManager.poolCycles(_secondPoolAddress))
          .currentCycleStartTime;
      });

      it("...should have 'None' state for non-registered pool", async () => {
        expect(
          await poolCycleManager.getCurrentCycleState(
            "0x9E775D89857E9ff1e76923fB45e296d3bf43b31f"
          )
        ).to.equal(0); // 0 = None
      });

      it("...should stay in 'Open' state when less time than openCycleDuration has passed", async () => {
        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(1); // 1 = Open

        // Move time forward by openCycleDuration - 30 seconds
        await moveForwardTime(_openCycleDuration.sub(30));

        // Verify current time is less than cycleStartTime + openCycleDuration
        const currentTime = BigNumber.from(
          (await ethers.provider.getBlock("latest")).timestamp
        );
        assert(currentTime < cycleStartTime.add(_openCycleDuration));

        await poolCycleManager.calculateAndSetPoolCycleState(
          _secondPoolAddress
        );

        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(1); // 1 = Open
        expect(
          await poolCycleManager.getCurrentCycleIndex(_secondPoolAddress)
        ).to.equal(0);
      });

      it("...should move to 'Locked' state after openCycleDuration has passed", async () => {
        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(1); // 1 = Open

        // Move time forward by time left in openCycleDuration
        await moveForwardTime(BigNumber.from(30));

        // Verify current time is greater than cycleStartTime + openCycleDuration
        const currentTime = BigNumber.from(
          (await ethers.provider.getBlock("latest")).timestamp
        );
        assert(currentTime > cycleStartTime.add(_openCycleDuration));

        await poolCycleManager.calculateAndSetPoolCycleState(
          _secondPoolAddress
        );

        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(2); // 2 = Locked
        expect(
          await poolCycleManager.getCurrentCycleIndex(_secondPoolAddress)
        ).to.equal(0);
      });

      it("...should stay in 'Locked' state when less time than cycleDuration has passed", async () => {
        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(2); // 2 = Locked

        // Move time forward by cycleDuration - 30 seconds
        const lessThanCycleDuration = _cycleDuration
          .sub(_openCycleDuration)
          .sub(30);
        await moveForwardTime(lessThanCycleDuration);

        // Verify current time is less than cycleStartTime + cycleDuration
        const currentTime = BigNumber.from(
          (await ethers.provider.getBlock("latest")).timestamp
        );
        assert(currentTime < cycleStartTime.add(_cycleDuration));

        await poolCycleManager.calculateAndSetPoolCycleState(
          _secondPoolAddress
        );

        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(2); // 2 = Locked
        expect(
          await poolCycleManager.getCurrentCycleIndex(_secondPoolAddress)
        ).to.equal(0);
      });

      it("...should create new cycle with 'Open' state after cycleDuration has passed", async () => {
        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(2); // 2 = Locked

        // Move time forward by time left in cycle
        await moveForwardTime(BigNumber.from(30));

        await poolCycleManager.calculateAndSetPoolCycleState(
          _secondPoolAddress
        );

        // Verify current time is greater than cycleStartTime + cycleDuration
        const currentTime = BigNumber.from(
          (await ethers.provider.getBlock("latest")).timestamp
        );
        assert(currentTime > cycleStartTime.add(_cycleDuration));

        expect(
          await poolCycleManager.getCurrentCycleState(_secondPoolAddress)
        ).to.equal(1); // 1 = Open
        expect(
          await poolCycleManager.getCurrentCycleIndex(_secondPoolAddress)
        ).to.equal(1);
      });
    });

    describe("upgrade", () => {
      let upgradedPoolCycleManager: PoolCycleManagerV2;

      it("... should revert when upgradeTo is called by non-owner", async () => {
        await expect(
          poolCycleManager
            .connect(account1)
            .upgradeTo("0xA18173d6cf19e4Cc5a7F63780Fe4738b12E8b781")
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("... should fail upon invalid upgrade", async () => {
        try {
          await upgrades.validateUpgrade(
            poolCycleManager.address,
            await ethers.getContractFactory("PoolCycleManagerV2NotUpgradable"),
            {
              kind: "uups"
            }
          );
        } catch (e: any) {
          expect(e.message).includes(
            "Contract `contracts/test/PoolCycleManagerV2.sol:PoolCycleManagerV2NotUpgradable` is not upgrade safe"
          );
        }
      });

      it("... should upgrade successfully", async () => {
        const poolCycleManagerV2Factory = await ethers.getContractFactory(
          "PoolCycleManagerV2"
        );

        // upgrade to v2
        upgradedPoolCycleManager = (await upgrades.upgradeProxy(
          poolCycleManager.address,
          poolCycleManagerV2Factory
        )) as PoolCycleManagerV2;
      });

      it("... should have same address after upgrade", async () => {
        expect(upgradedPoolCycleManager.address).to.be.equal(
          poolCycleManager.address
        );
      });

      it("... should be able to call new function in v2", async () => {
        const value = await upgradedPoolCycleManager.getVersion();
        expect(value).to.equal("v2");
      });

      it("... should be able to call existing function in v1", async () => {
        await upgradedPoolCycleManager.calculateAndSetPoolCycleState(
          _poolAddress
        );
      });
    });

    after(async () => {
      poolCycleManager
        .connect(deployer)
        .setContractFactory(contractFactoryAddress);
    });
  });
};

export { testPoolCycleManager };
