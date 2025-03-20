// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {USDT} from "../src/USDT.sol";

contract USDTScript is Script {
    USDT public usdt;

    address baseTokenAddress = vm.envAddress("HOLESKY_USDT");
    address feeWallet = vm.envAddress("PLATFORM_WALLET");
    address authorityAddress = vm.envAddress("AUTHORITY_ADDRESS");
    address ownerAddress = vm.envAddress("OWNER");
    uint256 public discountinPPM = 30_000;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        usdt = new USDT();
        vm.stopBroadcast();

        console.log("USDT deployed at:", address(usdt));
    }
}
