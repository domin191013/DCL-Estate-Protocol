// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../libraries/ERC721.sol";
import "../libraries/Transfer.sol";
import "../libraries/Fee.sol";
import "../libraries/Marketplace.sol";
import "../interfaces/IRentPayout.sol";

contract RentPayout is IRentPayout {
    modifier payout(uint256 tokenId) {
        payoutRent(tokenId);
        _;
    }

    /// @dev Pays out the accumulated rent for a given tokenId
    /// Rent is paid out to consumer if set, otherwise it is paid to the owner of the DCL Estate NFT
    function payoutRent(uint256 tokenId) internal {
        address paymentToken = Marketplace
            .marketplaceStorage()
            .assets[tokenId]
            .paymentToken;
        uint256 amount = Fee.clearAccumulatedRent(tokenId, paymentToken);
        if (amount == 0) {
            return;
        }

        address receiver = ERC721.consumerOf(tokenId);
        if (receiver == address(0)) {
            receiver = ERC721.ownerOf(tokenId);
        }

        Transfer.safeTransfer(paymentToken, receiver, amount);
        emit ClaimRentFee(tokenId, paymentToken, receiver, amount);
    }
}
