// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "../interfaces/IERC721Consumable.sol";
import "../interfaces/IMarketplaceFacet.sol";
import "../libraries/ERC721.sol";
import "../libraries/Transfer.sol";
import "../libraries/Fee.sol";
import "../libraries/Ownership.sol";
import "../libraries/Marketplace.sol";
import "../libraries/MetaverseConsumableAdapter.sol";
import "../libraries/RentLib.sol";
import "../libraries/RentPayout.sol";

contract MarketplaceFacet is IMarketplaceFacet, ERC721Holder, RentPayout {
    function list(
        uint256 _metaverseId,
        address _metaverseRegistry,
        uint256 _metaverseAssetId,
        uint256 _minPeriod,
        uint256 _maxPeriod,
        uint256 _maxFutureTime,
        address _paymentToken,
        uint256 _pricePerSecond
    ) external returns (uint256) {
        require(
            _metaverseRegistry != address(0),
            "_metaverseRegistry must not be 0x0"
        );
        require(
            Marketplace.supportsRegistry(_metaverseId, _metaverseRegistry),
            "_registry not supported"
        );
        require(_minPeriod != 0, "_minPeriod must not be 0");
        require(_maxPeriod != 0, "_maxPeriod must not be 0");
        require(_minPeriod <= _maxPeriod, "_minPeriod more than _maxPeriod");
        require(
            _maxPeriod <= _maxFutureTime,
            "_maxPeriod more than _maxFutureTime"
        );
        require(
            Fee.supportsTokenPayment(_paymentToken),
            "payment type not supported"
        );

        uint256 asset = ERC721.safeMint(msg.sender);

        Marketplace.MarketplaceStorage storage ms = Marketplace
            .marketplaceStorage();
        ms.assets[asset] = Marketplace.Asset({
            metaverseId: _metaverseId,
            metaverseRegistry: _metaverseRegistry,
            metaverseAssetId: _metaverseAssetId,
            paymentToken: _paymentToken,
            minPeriod: _minPeriod,
            maxPeriod: _maxPeriod,
            maxFutureTime: _maxFutureTime,
            pricePerSecond: _pricePerSecond,
            status: Marketplace.AssetStatus.Listed,
            totalRents: 0
        });

        Transfer.erc721SafeTransferFrom(
            _metaverseRegistry,
            msg.sender,
            address(this),
            _metaverseAssetId
        );

        emit List(
            asset,
            _metaverseId,
            _metaverseRegistry,
            _metaverseAssetId,
            _minPeriod,
            _maxPeriod,
            _maxFutureTime,
            _paymentToken,
            _pricePerSecond
        );
        return asset;
    }

    function updateConditions(
        uint256 _assetId,
        uint256 _minPeriod,
        uint256 _maxPeriod,
        uint256 _maxFutureTime,
        address _paymentToken,
        uint256 _pricePerSecond
    ) external payout(_assetId) {
        require(
            ERC721.isApprovedOrOwner(msg.sender, _assetId) ||
                ERC721.isConsumerOf(msg.sender, _assetId),
            "caller must be consumer, approved or owner of _assetId"
        );
        require(_minPeriod != 0, "_minPeriod must not be 0");
        require(_maxPeriod != 0, "_maxPeriod must not be 0");
        require(_minPeriod <= _maxPeriod, "_minPeriod more than _maxPeriod");
        require(
            _maxPeriod <= _maxFutureTime,
            "_maxPeriod more than _maxFutureTime"
        );
        require(
            Fee.supportsTokenPayment(_paymentToken),
            "payment type not supported"
        );

        Marketplace.MarketplaceStorage storage ms = Marketplace
            .marketplaceStorage();
        Marketplace.Asset storage asset = ms.assets[_assetId];
        asset.paymentToken = _paymentToken;
        asset.minPeriod = _minPeriod;
        asset.maxPeriod = _maxPeriod;
        asset.maxFutureTime = _maxFutureTime;
        asset.pricePerSecond = _pricePerSecond;

        emit UpdateConditions(
            _assetId,
            _minPeriod,
            _maxPeriod,
            _maxFutureTime,
            _paymentToken,
            _pricePerSecond
        );
    }

    function delist(uint256 _assetId) external {
        Marketplace.MarketplaceStorage storage ms = Marketplace
            .marketplaceStorage();
        require(
            ERC721.isApprovedOrOwner(msg.sender, _assetId),
            "caller must be approved or owner of _assetId"
        );

        Marketplace.Asset memory asset = ms.assets[_assetId];

        ms.assets[_assetId].status = Marketplace.AssetStatus.Delisted;

        emit Delist(_assetId, msg.sender);

        if (block.timestamp >= ms.rents[_assetId][asset.totalRents].end) {
            withdraw(_assetId);
        }
    }

    function withdraw(uint256 _assetId) public payout(_assetId) {
        Marketplace.MarketplaceStorage storage ms = Marketplace
            .marketplaceStorage();
        require(
            ERC721.isApprovedOrOwner(msg.sender, _assetId),
            "caller must be approved or owner of _assetId"
        );
        Marketplace.Asset memory asset = ms.assets[_assetId];
        require(
            asset.status == Marketplace.AssetStatus.Delisted,
            "_assetId not delisted"
        );
        require(
            block.timestamp >= ms.rents[_assetId][asset.totalRents].end,
            "_assetId has an active rent"
        );
        clearConsumer(asset);

        delete Marketplace.marketplaceStorage().assets[_assetId];
        address owner = ERC721.ownerOf(_assetId);
        ERC721.burn(_assetId);

        Transfer.erc721SafeTransferFrom(
            asset.metaverseRegistry,
            address(this),
            owner,
            asset.metaverseAssetId
        );

        emit Withdraw(_assetId, owner);
    }

    function rent(
        uint256 _assetId,
        uint256 _period,
        uint256 _maxRentStart,
        address _paymentToken,
        uint256 _amount
    ) external payable returns (uint256, bool) {
        (uint256 rentId, bool rentStartsNow) = RentLib.rent(
            RentLib.RentParams({
                _assetId: _assetId,
                _period: _period,
                _maxRentStart: _maxRentStart,
                _paymentToken: _paymentToken,
                _amount: _amount
            })
        );
        return (rentId, rentStartsNow);
    }

    function setMetaverseName(uint256 _metaverseId, string memory _name)
        external
    {
        Ownership.enforceIsContractOwner();
        Marketplace.setMetaverseName(_metaverseId, _name);

        emit SetMetaverseName(_metaverseId, _name);
    }

    function setRegistry(
        uint256 _metaverseId,
        address _registry,
        bool _status
    ) external {
        require(_registry != address(0), "_registry must not be 0x0");
        Ownership.enforceIsContractOwner();

        Marketplace.setRegistry(_metaverseId, _registry, _status);

        emit SetRegistry(_metaverseId, _registry, _status);
    }

    function metaverseName(uint256 _metaverseId)
        external
        view
        returns (string memory)
    {
        return Marketplace.metaverseName(_metaverseId);
    }

    function supportsRegistry(uint256 _metaverseId, address _registry)
        external
        view
        returns (bool)
    {
        return Marketplace.supportsRegistry(_metaverseId, _registry);
    }

    function totalRegistries(uint256 _metaverseId)
        external
        view
        returns (uint256)
    {
        return Marketplace.totalRegistries(_metaverseId);
    }

    function registryAt(uint256 _metaverseId, uint256 _index)
        external
        view
        returns (address)
    {
        return Marketplace.registryAt(_metaverseId, _index);
    }

    function assetAt(uint256 _assetId)
        external
        view
        returns (Marketplace.Asset memory)
    {
        return Marketplace.assetAt(_assetId);
    }

    function rentAt(uint256 _assetId, uint256 _rentId)
        external
        view
        returns (Marketplace.Rent memory)
    {
        return Marketplace.rentAt(_assetId, _rentId);
    }

    function clearConsumer(Marketplace.Asset memory asset) internal {
        address adapter = MetaverseConsumableAdapter
            .metaverseConsumableAdapterStorage()
            .consumableAdapters[asset.metaverseRegistry];

        if (adapter != address(0)) {
            IERC721Consumable(adapter).changeConsumer(
                address(0),
                asset.metaverseAssetId
            );
        }
    }
}
