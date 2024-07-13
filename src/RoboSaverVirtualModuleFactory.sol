// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IKeeperRegistrar} from "./interfaces/chainlink/IKeeperRegistrar.sol";

import {IDelayModifier} from "@gnosispay-kit/interfaces/IDelayModifier.sol";
import {IRolesModifier} from "@gnosispay-kit/interfaces/IRolesModifier.sol";

import {Factory} from "./types/DataTypes.sol";
import {Errors} from "./libraries/Errors.sol";

import {FactoryConstants} from "./abstracts/FactoryConstants.sol";

import {RoboSaverVirtualModule} from "./RoboSaverVirtualModule.sol";

/// @title RoboSaverVirtualModuleFactory
/// @author onchainification.xyz
/// @notice Factory contract creates an unique {RoboSaverVirtualModule} per Gnosis Pay card, and registers it in the Chainlink Keeper Registry
contract RoboSaverVirtualModuleFactory is
    FactoryConstants // 1 inherited component
{
    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    // card -> (module address, upkeep id)
    mapping(address => Factory.VirtualModuleDetails) public virtualModules;

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/
    event RoboSaverVirtualModuleCreated(address virtualModule, address card, uint256 upkeepId, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor() {
        /// @dev max approval to be able to handle smoothly upkeep creations and top-ups
        LINK.approve(address(CL_REGISTRAR), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  EXTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a virtual module for a card
    /// @param _delayModule The address of the delay module
    /// @param _rolesModule The address of the roles module
    /// @param _buffer The buffer for the virtual module (configurable)
    /// @param _slippage The slippage for the virtual module (configurable)
    function createVirtualModule(address _delayModule, address _rolesModule, uint256 _buffer, uint16 _slippage)
        external
    {
        /// @dev verification of `buffer` & `slippage` is done in the constructor of the virtual module
        _verifyVirtualModuleCreationArgs(_delayModule, _rolesModule);

        // uses `msg.sender` as a salt to make the deployed address of the virtual module deterministic
        address virtualModule = address(
            new RoboSaverVirtualModule{salt: keccak256(abi.encodePacked(msg.sender))}(
                address(this), _delayModule, _rolesModule, _buffer, _slippage
            )
        );

        uint256 upkeepId = _registerRoboSaverVirtualModule(virtualModule);

        // extracts forwarder address & sets keeper
        address keeper = CL_REGISTRY.getForwarder(upkeepId);
        RoboSaverVirtualModule(virtualModule).setKeeper(keeper);

        emit RoboSaverVirtualModuleCreated(virtualModule, msg.sender, upkeepId, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   INTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Verifies the arguments passed to the virtual module creation
    /// @param _delayModule The address of the delay module
    /// @param _rolesModule The address of the roles module
    function _verifyVirtualModuleCreationArgs(address _delayModule, address _rolesModule) internal view {
        // verify that delay module avatar & `msg.sender` matches
        if (IDelayModifier(_delayModule).avatar() != msg.sender) {
            revert Errors.CallerNotMatchingAvatar("DelayModule", msg.sender);
        }
        // verify that the roles module avatar & `msg.sender` matches
        if (IRolesModifier(_rolesModule).avatar() != msg.sender) {
            revert Errors.CallerNotMatchingAvatar("RolesModule", msg.sender);
        }
    }

    /// @notice Registers the virtual module in the Chainlink Keeper Registry
    /// @param _virtualModule The address of the virtual module to be registered
    function _registerRoboSaverVirtualModule(address _virtualModule) internal returns (uint256 upkeepId_) {
        IKeeperRegistrar.RegistrationParams memory registrationParams = IKeeperRegistrar.RegistrationParams({
            name: string.concat(RoboSaverVirtualModule(_virtualModule).name(), "-", _addressToString(msg.sender)),
            encryptedEmail: "",
            upkeepContract: _virtualModule,
            gasLimit: 2_000_000,
            adminAddress: 0xDb1b024855AC829681818aa7ED021f65509321b5, // @note temporarily eoa for testing
            triggerType: 0,
            checkData: "",
            triggerConfig: "",
            offchainConfig: "",
            amount: 2e18 // @note dummy value for now
        });

        upkeepId_ = CL_REGISTRAR.registerUpkeep(registrationParams);
        if (upkeepId_ == 0) revert Errors.UpkeepZero();

        virtualModules[msg.sender] =
            Factory.VirtualModuleDetails({virtualModuleAddress: _virtualModule, upkeepId: upkeepId_});
    }

    /// @notice Converts an address to a string
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
}
