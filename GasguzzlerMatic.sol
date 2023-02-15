// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "./utils/NonblockingLzApp.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract GasguzzlerMatic is ERC721EnumerableUpgradeable, OwnableUpgradeable, NonblockingLzApp {

    using StringsUpgradeable for uint;

    address public stakingContract;
    string public _tokenBaseURI;
    uint public gas;
    mapping (address => bool) public authorisedInteraction;

    event MintOnL2(address _user, uint tokenId);
    event BurnOnL2(address _user, uint tokenId);


    function init(string memory _name, string memory _symbol, address _endpointAddress, address _stakingContract) external initializer
    {
        __Ownable_init();
        __ERC721Enumerable_init();
        __ERC721_init(_name, _symbol);
        __nonblockingLzApp_init(_endpointAddress);
        stakingContract = _stakingContract;
        gas = 250000;
    }

    function addStakingContract(address _stakingContract) external onlyOwner {
        stakingContract = _stakingContract;
    }

    function mintTokens(address _to, uint[] memory tokenIds) internal {
        for (uint i=0; i< tokenIds.length; i++) {
            _mint(_to, tokenIds[i]);
            emit MintOnL2(_to, tokenIds[i]);
        }
    }

    function burnAuthorisedToken(address _from, uint id) external {
        require (authorisedInteraction[msg.sender],'Authorised Burn Only');
        _burn(id);
        emit BurnOnL2(_from, id);
    }

    function burnTokens(uint[] memory ids) internal {
        for (uint i=0; i<ids.length; i++)
        {
            require (ownerOf(ids[i]) == msg.sender,'Error: !Owner');
            _burn(ids[i]);
            emit BurnOnL2(msg.sender, ids[i]);
        }
    }

    function transferTokensToL1(uint256[] memory tokenIds, bytes memory _userAddress,  uint16 destinationChainId) external payable{
        burnTokens(tokenIds);
        bytes memory payload = abi.encode(_userAddress,tokenIds);
        uint16 version = 1;
        uint256 _gas = gas + (50000  * tokenIds.length);
        bytes memory adaptorParams = abi.encodePacked(version, _gas);
        (uint256 messageFees, ) = lzEndpoint.estimateFees(destinationChainId,address(this),payload,false,adaptorParams);
        require(msg.value > messageFees, 'Insufficient Amount Sent');
        _lzSend(destinationChainId,payload,payable(msg.sender),address(0),adaptorParams);
    }

    function _nonblockingLzReceive(
        uint16,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        (bytes memory toAddressBytes, uint256[] memory tokenIds) = abi.decode(
            _payload,
            (bytes,uint256[])
        );

        address _toAddress;
        assembly {
            _toAddress := mload(add(toAddressBytes,20))
        }
        mintTokens(_toAddress, tokenIds);
    }

    // Endpoint.sol estimateFees() returns the fees for the message
    function estimateFees(
        address userAddress,
        uint16 destinationChainId,
        uint[] memory tokenIds
    ) public view returns (uint256 nativeFee, uint256 zroFee) {
        return
        lzEndpoint.estimateFees(
            destinationChainId,
            address(this),
            abi.encode(userAddress, tokenIds),
            false,
            abi.encodePacked(uint16(1),uint256(gas + (50000  * tokenIds.length)))
            );
    }

    function setBaseURI(string calldata URI) external onlyOwner  {
        _tokenBaseURI = URI;
    }

    function forceMintTokens(address _to, uint id) external {
        require (authorisedInteraction[msg.sender],'Authorised Mint Only');
        _mint(_to,id);
        emit MintOnL2(_to,id);
    }

    function addAuthorisedMinter(address _minter) external onlyOwner {
        authorisedInteraction[_minter] = true;
    }

    function changeGas (uint _gasAmount) external onlyOwner {
        gas = _gasAmount;
    }

    function tokenURI(uint tokenId) public view override(ERC721Upgradeable) returns (string memory) {
        require(_exists(tokenId), "Cannot query non-existent token");
        return string(abi.encodePacked(_tokenBaseURI, tokenId.toString()));
    }

    function _mint(address to, uint256 tokenId) internal override virtual {
        _setApprovalForAll(to, stakingContract, true);
        super._mint(to, tokenId);
    }
}
