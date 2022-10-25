import { parseUSDC, getUsdcContract, impersonateCircle } from "../utils/usdc";
import { Contract } from "ethers";
import { ITranchedPool } from "../../typechain-types/contracts/external/goldfinch/ITranchedPool";

const payToLendingPool: Function = async (
  tranchedPool: ITranchedPool,
  amount: string,
  usdcContract: Contract
) => {
  const amountToPay = parseUSDC(amount);

  // Transfer USDC to lending pool's credit line
  await usdcContract
    .connect(await impersonateCircle())
    .transfer(await tranchedPool.creditLine(), amountToPay.toString());

  // assess lending pool
  await tranchedPool.assess();
};

export { payToLendingPool };
