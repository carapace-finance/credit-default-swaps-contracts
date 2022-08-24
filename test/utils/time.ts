import { BigNumber } from "@ethersproject/bignumber";
import { ethers, network } from "hardhat";

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

/**
 * Returns future timestamp by adding specified number of days to the current timestamp in seconds
 * @param days
 * @returns
 */
const getUnixTimestampAheadByDays: Function = async (days: number) => {
  return (await getLatestBlockTimestamp()) + days * 24 * 60 * 60;
};

/**
 * Move forward time by specified number of seconds and mines the block
 * @param _duration in seconds
 */
const moveForwardTime: Function = async (_duration: BigNumber) => {
  await network.provider.send("evm_increaseTime", [_duration.toNumber()]);
  await network.provider.send("evm_mine", []);
};

const getDaysInSeconds: Function = (days: number) => {
  return BigNumber.from(days * 24 * 60 * 60);
};

const getLatestBlockTimestamp: Function = async () => {
  return (await ethers.provider.getBlock("latest")).timestamp;
};

export {
  getUnixTimestampOfSomeMonthAhead,
  getUnixTimestampAheadByDays,
  moveForwardTime,
  getDaysInSeconds,
  getLatestBlockTimestamp
};
