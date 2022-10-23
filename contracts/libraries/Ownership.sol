// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./Diamond.sol";

library Ownership {
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function setContractOwner(address _newOwner) internal {
        Diamond.DiamondStorage storage ds = Diamond.diamondStorage();

        address previousOwner = ds.contractOwner;
        require(
            previousOwner != _newOwner,
            "Previous owner and new owner must be different"
        );

        ds.contractOwner = _newOwner;

        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = Diamond.diamondStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        require(
            msg.sender == Diamond.diamondStorage().contractOwner,
            "Must be contract owner"
        );
    }
}
