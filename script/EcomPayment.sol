// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {EcomPayment} from "../src/EcomPayment.sol";

contract EcomPaymentScript is Script {
    EcomPayment public ecomPayment;

    address baseTokenAddress = vm.envAddress("HOLESKY_USDT");
    address feeWallet = vm.envAddress("PLATFORM_WALLET");
    address authorityAddress = vm.envAddress("AUTHORITY_ADDRESS");
    address ownerAddress = vm.envAddress("OWNER");
    uint256 public discountinPPM = 30_000;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        ecomPayment = new EcomPayment(
            feeWallet,
            authorityAddress,
            baseTokenAddress,
            ownerAddress,
            discountinPPM
        );
        vm.stopBroadcast();

        console.log("EcomPayment deployed at:", address(ecomPayment));
    }
}
