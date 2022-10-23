// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./libraries/Diamond.sol";
import "./libraries/Ownership.sol";
import "./interfaces/IDiamondCut.sol";
import "./interfaces/IDiamondLoupe.sol";

contract EstateDiamond {
    constructor(IDiamondCut.FacetCut[] memory _diamondCut, address _owner) {
        require(_owner != address(0), "owner must not be 0x0");

        Ownership.setContractOwner(_owner);
        Diamond.diamondCut(_diamondCut, address(0), new bytes(0));

        Diamond.DiamondStorage storage ds = Diamond.diamondStorage();
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
    }

    // Find facet for function that is called and execute the
    // function if a facet is found and return any value.
    fallback() external payable {
        Diamond.DiamondStorage storage ds = Diamond.diamondStorage();

        // get facet from function selector
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        require(facet != address(0), "Diamond: Function does not exist");
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
