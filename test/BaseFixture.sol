// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {Delay} from "@delay-module/Delay.sol";
import {Roles} from "@roles-module/Roles.sol";
import {Bouncer} from "@gnosispay-kit/Bouncer.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol"; // contains internally also IERC20
import "@balancer-v2/interfaces/contracts/pool-stable/StablePoolUserData.sol";

import {RoboSaverVirtualModuleFactory} from "../src/RoboSaverVirtualModuleFactory.sol";
import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

import {ISafe} from "@gnosispay-kit/interfaces/ISafe.sol";
import {IEURe} from "../src/interfaces/eure/IEURe.sol";

import {Constants} from "./utils/Constants.sol";

contract BaseFixture is Test, Constants {
    // gnosis pay modules
    Delay delayModule;
    Roles rolesModule;

    Bouncer bouncerContract;

    ISafe safe;

    // robosaver module & factory
    RoboSaverVirtualModuleFactory roboModuleFactory;
    RoboSaverVirtualModule roboModule;

    // Keeper address (forwarder): https://docs.chain.link/chainlink-automation/guides/forwarder#securing-your-upkeep
    address keeper;

    function setUp() public virtual {
        vm.createSelectFork("gnosis");

        // deploy fresh safe instance
        address[] memory safeOwners = new address[](1);
        safeOwners[0] = SAFE_EOA_SIGNER;

        bytes memory initializer = abi.encodeWithSelector(
            ISafe.setup.selector,
            safeOwners, // owners
            1, // threshold
            address(0), // to
            abi.encode(0), // data
            address(0), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            payable(address(0)) // paymentReceiver
        );

        safe = ISafe(payable(address(SAFE_FACTORY.createProxyWithNonce(SAFE_SINGLETON, initializer, 50))));

        // module deployments to mirror gnosis pay setup: delay & roles
        rolesModule = new Roles(SAFE_EOA_SIGNER, address(safe), address(safe));
        delayModule = new Delay(address(safe), address(safe), address(safe), COOLDOWN_PERIOD, EXPIRATION_PERIOD);

        bouncerContract = new Bouncer(address(safe), address(rolesModule), SET_ALLOWANCE_SELECTOR);

        roboModuleFactory = new RoboSaverVirtualModuleFactory();
        // fund the factory with LINK for task top up
        deal(LINK, address(roboModuleFactory), LINK_FOR_TASK_TOP_UP);

        // enable robo module in the delay & gnosis safe for tests flow
        vm.startPrank(address(safe));

        // create from factory new robo virtual module
        roboModuleFactory.createVirtualModule(address(delayModule), address(rolesModule), EURE_BUFFER, SLIPPAGE);
        (address roboModuleAddress, uint256 upkeepId) = roboModuleFactory.virtualModules(address(safe));

        roboModule = RoboSaverVirtualModule(roboModuleAddress);
        // deduct keeper from the registry and factory upkeep id rerieved from factory storage
        keeper = CL_REGISTRY.getForwarder(upkeepId);

        delayModule.enableModule(address(roboModule));
        delayModule.enableModule(address(safe));

        safe.enableModule(address(delayModule));
        safe.enableModule(address(rolesModule));

        vm.stopPrank();

        vm.prank(SAFE_EOA_SIGNER);
        rolesModule.setAllowance(
            SET_ALLOWANCE_KEY,
            MIN_EURE_ALLOWANCE,
            MIN_EURE_ALLOWANCE,
            MIN_EURE_ALLOWANCE,
            ALLOWANCE_PERIOD,
            uint64(block.timestamp)
        );

        // @note is it neccesary for our setup: assign roles, scope target, scope function?

        vm.prank(SAFE_EOA_SIGNER);
        rolesModule.transferOwnership(address(bouncerContract));

        vm.prank(EURE_MINTER);
        IEURe(EURE).mintTo(address(safe), EURE_TO_MINT);

        deal(AURA_GAUGE_STEUR_EURE, address(safe), EURE_TO_MINT);

        // assert here constructor action in the {RoboSaverVirtualModuleFactory} for a hit
        assertEq(IERC20(LINK).allowance(address(roboModuleFactory), address(CL_REGISTRAR)), type(uint256).max);

        _labelKeyContracts();
    }

    /// @dev Labels key contracts for tracing
    function _labelKeyContracts() internal {
        vm.label(address(safe), "GNOSIS_SAFE");
        // robosaver module factory
        vm.label(address(roboModuleFactory), "ROBO_MODULE_FACTORY");
        // tokens
        vm.label(EURE, "EURE");
        vm.label(WETH, "WETH");
        vm.label(LINK, "LINK");
        // gnosis pay modules infrastructure
        vm.label(address(delayModule), "DELAY_MODULE");
        vm.label(address(bouncerContract), "BOUNCER_CONTRACT");
        vm.label(address(rolesModule), "ROLES_MODULE");
        vm.label(address(roboModule), "ROBO_MODULE");
        // balancer
        vm.label(BPT_STEUR_EURE, "BPT_STEUR_EURE");
        vm.label(AURA_GAUGE_STEUR_EURE, "AURA_GAUGE_STEUR_EURE");
        vm.label(address(roboModule.BALANCER_VAULT()), "BALANCER_VAULT");
        // chainlink
        vm.label(address(CL_REGISTRY), "CL_REGISTRY");
        vm.label(address(CL_REGISTRAR), "CL_REGISTRAR");
    }

    function _getDeterministicAddress(bytes memory bytecode, bytes32 _salt) internal view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }

    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }

    // ref: https://github.com/ethereum/solidity/issues/14996
    function _extractEncodeDataWithoutSelector(bytes memory myData) public pure returns (bytes memory, bytes4) {
        uint256 BYTES4_SIZE = 4;
        uint256 bytesSize = myData.length - BYTES4_SIZE;
        bytes memory dataWithoutSelector = new bytes(bytesSize);
        for (uint8 i = 0; i < bytesSize; i++) {
            dataWithoutSelector[i] = myData[i + BYTES4_SIZE];
        }
        bytes4 selector = bytes4(myData);
        return (dataWithoutSelector, selector);
    }

    /// @notice Helper to transfer out EURE from the safe to simulate being below the threshold of daily allowance
    function _transferOutBelowThreshold() internal returns (uint256 tokenAmountTargetToMove_) {
        uint256 eureBalance = IERC20(EURE).balanceOf(address(safe));

        (, uint128 maxRefill,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        tokenAmountTargetToMove_ = eureBalance - maxRefill + 100e18;

        bytes memory payloadErc20Transfer =
            abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove_);

        vm.prank(address(safe));
        delayModule.execTransactionFromModule(EURE, 0, payloadErc20Transfer, Enum.Operation.Call);
    }

    /*//////////////////////////////////////////////////////////////////////////
        INTERNAL METHODS: HELPERS FOR ASSERTING `queuedTx` STORAGE VALUES
    //////////////////////////////////////////////////////////////////////////*/

    function _assertPreStorageValuesNextTxExec(address _expectedTarget, bytes memory _eventPayloadGenerated)
        internal
        view
    {
        (uint256 nonce, address target, bytes memory payload) = roboModule.queuedTx();
        assertGt(nonce, 0);
        assertEq(target, _expectedTarget);
        assertEq(payload, _eventPayloadGenerated);
    }

    function _assertPostDefaultValuesNextTxExec() internal view {
        bytes memory emptyBytes;
        (uint256 nonce, address target, bytes memory payload) = roboModule.queuedTx();
        assertEq(nonce, 0);
        assertEq(target, address(0));
        assertEq(payload, emptyBytes);
    }

    /*//////////////////////////////////////////////////////////////////////////
                INTERNAL METHODS: HELPERS FOR `checker` ASSERTS
    //////////////////////////////////////////////////////////////////////////*/

    function _assertCheckerFalseNoDeficitNorSurplus() internal view {
        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");

        assertFalse(canExec);
        assertEq(execPayload, bytes("Neither deficit nor surplus; no action needed"));
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INTERNAL METHODS: BALANCER QUERY HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _getBptOutExpected(uint256 _amount) internal returns (uint256 bptOutExpected_) {
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[roboModule.EURE_TOKEN_BPT_INDEX()] = _amount;

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[1] = _amount;

        IAsset[] memory assets = new IAsset[](3);
        for (uint256 i; i < assets.length; i++) {
            assets[i] = roboModule.poolAssets(i);
        }

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            assets,
            maxAmountsIn,
            abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, 0),
            false
        );

        (bptOutExpected_,) = BALANCER_QUERIES.queryJoin(
            roboModule.BPT_STEUR_EURE_POOL_ID(), roboModule.CARD(), roboModule.CARD(), request
        );

        // naive: sanity check
        assertGt(bptOutExpected_, 0);
    }

    function _getMaxBptInExpected(uint256 _amount, uint256 _bptBalance) internal returns (uint256 bptInExpected_) {
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[roboModule.EURE_TOKEN_BPT_INDEX()] = _amount;

        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[1] = _amount;

        IAsset[] memory assets = new IAsset[](3);
        for (uint256 i; i < assets.length; i++) {
            assets[i] = roboModule.poolAssets(i);
        }

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest(
            assets,
            minAmountsOut,
            abi.encode(StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, _bptBalance),
            false
        );

        (bptInExpected_,) = BALANCER_QUERIES.queryExit(
            roboModule.BPT_STEUR_EURE_POOL_ID(), roboModule.CARD(), roboModule.CARD(), request
        );

        // naive: sanity check
        assertGt(bptInExpected_, 0);
    }
}
