import { ethers } from "hardhat"
const { BigNumber } = require("ethers")

export const BASE_TEN = 10
export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000"
export const MAX_UINT256 =  "0xffffffffffffffffffffffffffffffffffffffff"

export function encodeParameters(types:any, values:any) {
  const abi = new ethers.utils.AbiCoder()
  return abi.encode(types, values)
}

// Defaults to e18 using amount * 10^18
export function getBigNumber(amount:any, decimals = 18) {
  return BigNumber.from(amount).mul(BigNumber.from(BASE_TEN).pow(decimals))
}

export * from "./time"
