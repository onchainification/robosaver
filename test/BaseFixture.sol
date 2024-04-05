// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {Delay} from "delay-module/Delay.sol";

import {RoboSaverModule} from "../src/RoboSaverModule.sol";

import {ISafe} from "../src/interfaces/safe/ISafe.sol";
import {IEURe} from "../src/interfaces/eure/IEURe.sol";

contract BaseFixture is Test {
    using stdStorage for StdStorage;

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    uint256 constant COOL_DOWN_PERIOD = 180; // 3 minutes
    uint256 constant EXPIRATION_PERIOD = 1800; // 30 minutes

    address constant EUR_E = 0xcB444e90D8198415266c6a2724b7900fb12FC56E;
    address constant WETH = 0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1;

    address constant EUR_E_MINTER = 0x882145B1F9764372125861727d7bE616c84010Ef;

    address constant GNOSIS_SAFE = 0xa4A4a4879dCD3289312884e9eC74Ed37f9a92a55;

    Delay delayModule;
    ISafe safe;
    RoboSaverModule roboModule;

    function setUp() public {
        // https://gnosisscan.io/block/33288902
        vm.createSelectFork("gnosis", 33288902);

        safe = ISafe(payable(GNOSIS_SAFE));
        delayModule = new Delay(GNOSIS_SAFE, GNOSIS_SAFE, GNOSIS_SAFE, COOL_DOWN_PERIOD, EXPIRATION_PERIOD);

        roboModule = new RoboSaverModule(address(delayModule));

        vm.prank(GNOSIS_SAFE);
        delayModule.enableModule(address(roboModule));

        vm.prank(GNOSIS_SAFE);
        safe.enableModule(address(delayModule));

        vm.prank(EUR_E_MINTER);
        IEURe(EUR_E).mintTo(GNOSIS_SAFE, 100e18);

        vm.label(EUR_E, "EUR_E");
        vm.label(WETH, "WETH");
        vm.label(GNOSIS_SAFE, "GNOSIS_SAFE");
        vm.label(address(delayModule), "DELAY_MODULE");
    }
}
