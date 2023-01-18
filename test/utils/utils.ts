import { Signer } from "ethers";
import { ethers } from "hardhat";
import { deployer } from "../../utils/deploy";

export const impersonateSignerWithEth = async (
  address: string,
  ethValue: string
): Promise<Signer> => {
  const signer = await ethers.getImpersonatedSigner(address);
  // send ethValue to address
  await deployer.sendTransaction({
    to: address,
    value: ethers.utils.parseEther(ethValue)
  });
  return signer;
};
