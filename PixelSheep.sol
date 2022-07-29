// SPDX-License-Identifier: MIT

 
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PixelSheep is ERC721Enumerable, Ownable {
    using Strings for uint256;

    //NEED TO MODIFY FOR PRODUCTION
    bool public paused = false; 
    
    uint256 public cost = 2000000000000000000;//2 tfuel in wei
    uint256 public maxSupply = 5;
    uint256 public maxMintAmount = 1;
    uint256 public nftPerAddressLimit = 1;
    
    //for gasless whitelist
    address private mintPass_publickey;
    struct MintPass {
        address message; //contains whitelisted user's public key + salt
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    string public baseURI;
    bool public onlyWhitelisted = true;
    uint256 public burnt = 0;
    mapping(address => uint256) public addressMintedBalance;

    // contract of next NFT release - assigned through onlyOwner function
    address public wolfContract;

    event Minted(address addr, string message);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initBaseURI, 
        address _mintPass_publickey
    ) ERC721(_name, _symbol) {
        setBaseURI(_initBaseURI);
        setMintPassPublicKey(_mintPass_publickey);
    }

    // INTERNAL
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // PUBLIC
    // front end passes a predetermined MintPass (json) that contains hash of user's address 
    // signed with an off chain admin keypair to verify whitelist status
    function mint(MintPass memory _mintPass, uint256 _mintAmount) public payable {
        require(!paused, "the contract is paused");
        uint256 numAlreadyMinted = totalSupply(); //number already minted
        require(_mintAmount > 0, "you need to mint at least 1 NFT");
        require(_mintAmount <= maxMintAmount, "max mint amount per session exceeded" );
        require(numAlreadyMinted + _mintAmount <= maxSupply, "There aren't this many NFTs left.");

        if (onlyWhitelisted == true) {
            //hash senders address to validate whitelist status
            bytes32 digest = keccak256(abi.encode(0, msg.sender));
            require(approveSender(digest, _mintPass), "MintPass missing or invalid" );

            //verify NFTs owned is less than max allowed
            require(addressMintedBalance[msg.sender] + _mintAmount <= nftPerAddressLimit, "max NFT per address exceeded" );
        }

        //check funds and mint
        require(msg.value >= cost * _mintAmount, "Insufficient funds");
        for (uint256 i = 1; i <= _mintAmount; i++) {
            addressMintedBalance[msg.sender]++;
            _safeMint(msg.sender, numAlreadyMinted + i);
        }

    }

    // returns avaialable, max supply, and # burnt for front end display
    function howMany() public view returns (string memory, string memory, string memory) {
        uint256 remaining = maxSupply - totalSupply();
        return (Strings.toString(maxSupply), Strings.toString(remaining), Strings.toString(burnt));
    }

    // return token IDs of current wallet
    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    // return token URI
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory){
        require( _exists(_tokenId), "ERC721Metadata: URI query for nonexistent token" );
        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 ? string( abi.encodePacked( currentBaseURI, _tokenId.toString(), ".json" ) ) : "";
    }

    // PRIVATE
    // validate MintPass : message == msg.sender & signer == adminKey
    function approveSender(bytes32 _digest, MintPass memory _mintPass) private view returns (bool) {
        address signer = ecrecover(_digest, _mintPass.v, _mintPass.r, _mintPass.s);
        //require(signer != address(0), "ECDSA: invalid signature");
        require(signer == mintPass_publickey, "MintPass invalid");
        bytes32 messageHash = keccak256(abi.encode(0, _mintPass.message));
        require( _digest == messageHash, "MintPass is not Valid for this address" );

        return true;
    }

    //ONLY OWNER
   
    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setMintPassPublicKey(address _mintPass_publickey) public onlyOwner{
        mintPass_publickey = _mintPass_publickey;
    } 

    function withdraw() public payable onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    // so 43A 96B 374 411
    function setWolfContract(address _addy) public onlyOwner returns (address){
        wolfContract = _addy;
        return wolfContract;
    }


    // EXTERNAL 
    // burn nft if function is called from registered contract by owner of a sheep
    function burnNFT(address _signer, uint256 _tokenId) external returns(bool){ 
        //check if token exists, if burn request is from the wolf contract, 
        //and if burn request initiator is token owner (passed from wolf contract)
        require( _exists(_tokenId), "This Sheep doesn't exist." );
        require( keccak256(abi.encodePacked(msg.sender)) == keccak256(abi.encodePacked(wolfContract)), "Only Wolves can eat Sheep.");    
        require( keccak256(abi.encodePacked(_signer)) == keccak256(abi.encodePacked(ownerOf(_tokenId))), "You cannot eat a sheep that you don't own");    

        _burn(_tokenId);
        burnt++;
        return true;
    }

}
