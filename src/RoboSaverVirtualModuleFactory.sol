// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IKeeperRegistryMaster} from "@chainlink/automation/interfaces/v2_1/IKeeperRegistryMaster.sol";
import {IKeeperRegistrar} from "./interfaces/chainlink/IKeeperRegistrar.sol";

import {RoboSaverVirtualModule} from "./RoboSaverVirtualModule.sol";

contract RoboSaverVirtualModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                     DATA TYPES
    //////////////////////////////////////////////////////////////////////////*/
    struct VirtualModuleDetails {
        address virtualModuleAddress;
        uint256 upkeepId;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    IKeeperRegistryMaster constant CL_REGISTRY = IKeeperRegistryMaster(0x299c92a219F61a82E91d2062A262f7157F155AC1);
    IKeeperRegistrar constant CL_REGISTRAR = IKeeperRegistrar(0x0F7E163446AAb41DB5375AbdeE2c3eCC56D9aA32);

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    // card -> (module address, upkeep id)
    mapping(address => VirtualModuleDetails) public virtualModules;

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/
    event RoboSaverVirtualModuleCreated(address virtualModule, address card, uint256 upkeepId, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////////////////
                                       ERRORS
    //////////////////////////////////////////////////////////////////////////*/
    error UpkeepZero();

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor() {}

    /*//////////////////////////////////////////////////////////////////////////
                                  EXTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Creates a virtual module for a card
    /// @param _delayModule The address of the delay module
    /// @param _roleModule The address of the role module
    /// @param _buffer The buffer for the virtual module (configurable)
    /// @param _slippage The slippage for the virtual module (configurable)
    function createVirtualModule(address _delayModule, address _roleModule, uint256 _buffer, uint16 _slippage)
        external
    {
        // @todo sanity checks on the inputs!

        // uses `CARD` address has to helps pre-determining the address of the virtual module given the salt
        address virtualModule = address(
            new RoboSaverVirtualModule{salt: keccak256(abi.encodePacked(msg.sender))}(
                address(this), _delayModule, _roleModule, _buffer, _slippage
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

    /// @notice Registers the virtual module in the Chainlink Keeper Registry
    /// @param _virtualModule The address of the virtual module to be registered
    function _registerRoboSaverVirtualModule(address _virtualModule) internal returns (uint256 upkeepId_) {
        IKeeperRegistrar.RegistrationParams memory registrationParams = IKeeperRegistrar.RegistrationParams({
            name: string.concat(RoboSaverVirtualModule(_virtualModule).name(), "-", _addressToString(msg.sender)),
            encryptedEmail: "",
            upkeepContract: _virtualModule,
            gasLimit: 2_000_000, // @todo optimise from the gas logs the right value. perhaps we are overshooting
            adminAddress: address(this), // @note the factory is the admin
            triggerType: 0,
            checkData: "",
            triggerConfig: "",
            offchainConfig: "",
            amount: 5e18 // @note dummy value for now
        });

        upkeepId_ = CL_REGISTRAR.registerUpkeep(registrationParams);
        if (upkeepId_ == 0) revert UpkeepZero();

        virtualModules[msg.sender] = VirtualModuleDetails({virtualModuleAddress: _virtualModule, upkeepId: upkeepId_});
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
