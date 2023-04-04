import { ethers } from "hardhat";

// TODO: update following vars before executing script
const MULTI_SIG_WALLET_ADDRESS = "";
const CONTRACT_ADDRESSES: string[] = [];

(async () => {
  // iterate over all contracts and transfer ownership to multi-sig wallet
  for (let i = 0; i < CONTRACT_ADDRESSES.length; i++) {
    const contractAddress = CONTRACT_ADDRESSES[i];
    const contract = await ethers.getContractAt(
      "OwnableUpgradeable",
      contractAddress
    );
    const owner = await contract.owner();
    console.log(`Contract ${contractAddress} is owned by ${owner}`);
    if (owner !== MULTI_SIG_WALLET_ADDRESS) {
      console.log(
        `Transferring ownership of contract ${contractAddress} to multi-sig wallet...`
      );
      const tx = await contract.transferOwnership(MULTI_SIG_WALLET_ADDRESS);
      await tx.wait();
      console.log(
        `Ownership of contract ${contractAddress} transferred to multi-sig wallet ${MULTI_SIG_WALLET_ADDRESS}`
      );
    } else {
      console.log(
        `Contract ${contractAddress} is already owned by multi-sig wallet ${MULTI_SIG_WALLET_ADDRESS}`
      );
    }
  }
})().catch((err) => {
  console.error(err);
});
