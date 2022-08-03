import { BigNumber } from "@ethersproject/bignumber";
import { network } from "hardhat";

const getUnixTimestampOfSomeMonthAhead: Function = async (months: number) => {
  let _expirationTime: number;
  let _date: Date = new Date();
  // Set the date to some months later
  _date.setMonth(_date.getMonth() + months);
  // Zero the time component
  _date.setHours(0, 0, 0, 0);
  // Get the time value in milliseconds and convert to seconds
  _expirationTime = _date.getTime() / 1000;
  return _expirationTime;
};

const moveForwardTime: Function = async (_duration: BigNumber) => {
  await network.provider.send("evm_increaseTime", [_duration.toNumber()]);
  await network.provider.send("evm_mine", []);
};

export { getUnixTimestampOfSomeMonthAhead, moveForwardTime };
