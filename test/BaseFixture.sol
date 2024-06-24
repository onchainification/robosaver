// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {Delay} from "@delay-module/Delay.sol";
import {Roles} from "@roles-module/Roles.sol";
import {Bouncer} from "@gnosispay-kit/Bouncer.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol"; // contains internally also IERC20
import {IBalancerQueries} from "@balancer-v2/interfaces/contracts/standalone-utils/IBalancerQueries.sol";
import "@balancer-v2/interfaces/contracts/pool-stable/StablePoolUserData.sol";

import {IKeeperRegistryMaster} from "@chainlink/automation/interfaces/v2_1/IKeeperRegistryMaster.sol";
import {IKeeperRegistrar} from "../src/interfaces/chainlink/IKeeperRegistrar.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

import {ISafeProxyFactory} from "@gnosispay-kit/interfaces/ISafeProxyFactory.sol";
import {ISafe} from "@gnosispay-kit/interfaces/ISafe.sol";
import {IEURe} from "../src/interfaces/eure/IEURe.sol";

contract BaseFixture is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    uint256 constant DIFF_MIN_OUT_CALC_ALLOWED = 70000000000000; // 0.00007 ether units

    uint16 constant SLIPPAGE = 200; // 2%

    // @note eure mint: daily allowance + buffer - 1 (to trigger a state of `canExec` = false)
    uint256 constant EURE_TO_MINT = 240e18;
    uint128 constant MIN_EURE_ALLOWANCE = 200e18;
    uint256 constant EURE_BUFFER = 50e18;

    ISafeProxyFactory constant SAFE_FACTORY = ISafeProxyFactory(0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2);
    address constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address constant SAFE_EOA_SIGNER = address(5454656565);

    // delay config
    uint256 constant COOLDOWN_PERIOD = 180; // 3 minutes
    uint256 constant EXPIRATION_PERIOD = 1800; // 30 minutes

    // roles config
    uint64 constant ALLOWANCE_PERIOD = 1 days;
    bytes4 constant TRANSFER_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    // bouncer config
    bytes4 constant SET_ALLOWANCE_SELECTOR =
        bytes4(keccak256(bytes("setAllowance(bytes32,uint128,uint128,uint128,uint64,uint64)"))); // 0xa8ec43ee
    bytes32 constant SET_ALLOWANCE_KEY = keccak256("SPENDING_ALLOWANCE");

    // tokens
    address constant EURE = 0xcB444e90D8198415266c6a2724b7900fb12FC56E;
    address constant WETH = 0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1;
    address constant BPT_STEUR_EURE = 0x06135A9Ae830476d3a941baE9010B63732a055F4;
    address constant LINK = 0xE2e73A1c69ecF83F464EFCE6A5be353a37cA09b2;

    address constant EURE_MINTER = 0x882145B1F9764372125861727d7bE616c84010Ef;

    bytes4 constant ADJUST_POOL_SELECTOR = 0xba2f0056;

    // balancer helper
    IBalancerQueries constant BALANCER_QUERIES = IBalancerQueries(0x0F3e0c4218b7b0108a3643cFe9D3ec0d4F57c54e);

    // CL: https://docs.chain.link/chainlink-automation/overview/supported-networks#gnosis-chain-xdai
    IKeeperRegistryMaster constant CL_REGISTRY = IKeeperRegistryMaster(0x299c92a219F61a82E91d2062A262f7157F155AC1);
    IKeeperRegistrar constant CL_REGISTRAR = IKeeperRegistrar(0x0F7E163446AAb41DB5375AbdeE2c3eCC56D9aA32);

    uint96 constant LINK_FOR_TASK_TOP_UP = 1_000e18; // plenty of funds

    // gnosis pay modules
    Delay delayModule;
    Roles rolesModule;

    Bouncer bouncerContract;

    ISafe safe;

    // robosaver module
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

        roboModule = new RoboSaverVirtualModule(address(delayModule), address(rolesModule), EURE_BUFFER, SLIPPAGE);

        // enable robo module in the delay & gnosis safe for tests flow
        vm.startPrank(address(safe));

        delayModule.enableModule(address(roboModule));
        delayModule.enableModule(address(safe));

        safe.enableModule(address(delayModule));
        safe.enableModule(address(rolesModule));

        // registering the task in CL automation service
        deal(LINK, address(safe), LINK_FOR_TASK_TOP_UP);
        IERC20(LINK).approve(address(CL_REGISTRAR), LINK_FOR_TASK_TOP_UP);

        IKeeperRegistrar.RegistrationParams memory registrationParams = IKeeperRegistrar.RegistrationParams({
            name: string.concat(roboModule.name(), "-", _addressToString(address(safe))),
            encryptedEmail: "",
            upkeepContract: address(roboModule),
            gasLimit: 2_000_000,
            adminAddress: address(safe),
            triggerType: 0,
            checkData: "",
            triggerConfig: "",
            offchainConfig: "",
            amount: LINK_FOR_TASK_TOP_UP
        });

        uint256 upkeepID = CL_REGISTRAR.registerUpkeep(registrationParams);
        assertNotEq(upkeepID, 0);

        keeper = CL_REGISTRY.getForwarder(upkeepID);
        roboModule.setKeeper(keeper);

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

        // @note pendant of wiring up a keeper service here at some point

        vm.prank(SAFE_EOA_SIGNER);
        rolesModule.transferOwnership(address(bouncerContract));

        vm.prank(EURE_MINTER);
        IEURe(EURE).mintTo(address(safe), EURE_TO_MINT);

        deal(BPT_STEUR_EURE, address(safe), EURE_TO_MINT);

        vm.label(EURE, "EURE");
        vm.label(WETH, "WETH");
        vm.label(address(safe), "GNOSIS_SAFE");
        vm.label(address(delayModule), "DELAY_MODULE");
        vm.label(address(bouncerContract), "BOUNCER_CONTRACT");
        vm.label(address(rolesModule), "ROLES_MODULE");
        vm.label(address(roboModule), "ROBO_MODULE");
        vm.label(BPT_STEUR_EURE, "BPT_STEUR_EURE");
        vm.label(address(roboModule.BALANCER_VAULT()), "BALANCER_VAULT");
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
